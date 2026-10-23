module vjsx

import sync
import net.urllib

@[params]
pub struct WebSocketConfig {
pub:
	max_connections    int = 32
	queue_capacity     int = 64
	max_message_bytes  int = 1024 * 1024
	max_queued_bytes   int = 4 * 1024 * 1024
	connect_timeout_ms int = 10000
	io_timeout_ms      int = 10000
	ca_file            string
}

struct WebSocketEvent {
	kind  string
	bytes []u8
	text  string
	code  int
	clean bool
}

// Workers retain this object only: no Context, Value, or session pointer.
@[heap]
struct WebSocketWorker {
	guard         &sync.Mutex = sync.new_mutex()
	config        WebSocketConfig
	command_read  int
	command_write int
	notify_write  int
	ready_state   &RuntimeHostStreamReadyState
	id            u64
mut:
	events           []WebSocketEvent
	event_bytes      int
	commands         []WebSocketEvent
	command_bytes    int
	stopped          bool
	cancel_requested bool
	terminal         bool
}

struct WebSocketRecord {
	worker      &WebSocketWorker
	callback    Value
	thread      thread
	notify_read int
}

@[heap]
struct WebSocketHost {
mut:
	records map[u64]WebSocketRecord
	next_id u64 = 1
	closed  bool
}

fn (mut worker WebSocketWorker) emit(event WebSocketEvent) bool {
	worker.guard.lock()
	if worker.stopped || worker.terminal {
		worker.guard.unlock()
		return false
	}
	mut accepted := true
	if event.kind != 'close' && (worker.events.len >= worker.config.queue_capacity
		|| worker.event_bytes + event.bytes.len > worker.config.max_queued_bytes) {
		// Reserve one terminal event even when the data budget is exhausted.
		worker.events << WebSocketEvent{ kind: 'error', text: 'WebSocket receive queue limit exceeded' }
		worker.events << WebSocketEvent{ kind: 'close', code: 1006 }
		worker.terminal = true
		accepted = false
	} else {
		worker.events << event
		worker.event_bytes += event.bytes.len
		if event.kind == 'close' { worker.terminal = true }
	}
	C.vjsx_ws_signal(worker.notify_write)
	worker.guard.unlock()
	mut ready := worker.ready_state
	ready.guard.lock()
	callback := ready.ready_fn
	session_id := ready.session_id
	closed := ready.closed
	ready.guard.unlock()
	if !closed {
		callback(RuntimeHostAsyncReadyRequest{ session_id: session_id, operation_id: worker.id })
	}
	return accepted
}

fn (mut worker WebSocketWorker) stop() {
	worker.guard.lock()
	worker.stopped = true
	C.vjsx_ws_signal(worker.command_write)
	worker.guard.unlock()
}

// Explicit installation supports both the QuickJS stdlib driver and embedders
// that drain session events on their own owning lane.
pub fn (mut session RuntimeSession) try_install_websocket(config WebSocketConfig) ! {
	if session.is_closed() { return error('runtime session is closed') }
	session.context.try_install_websocket_host(config, mut session.context.websocket_host, session.host_async_state, session.context.host_policy)!
}

pub fn (ctx &Context) try_install_websocket_globals(config WebSocketConfig) ! {
	ctx.try_install_websocket_host(config, mut ctx.websocket_host, ctx.host_cleanup_state.host_async, ctx.host_policy)!
}

pub fn (ctx &Context) try_install_websocket_globals_policy(config WebSocketConfig, policy HostPolicy) ! {
	ctx.try_install_websocket_host(config, mut ctx.websocket_host, ctx.host_cleanup_state.host_async, policy)!
}

fn (ctx &Context) try_install_websocket_host(config WebSocketConfig, mut host WebSocketHost, ready &RuntimeHostAsyncState, policy HostPolicy) ! {
	if config.max_connections < 1 || config.queue_capacity < 1 || config.max_message_bytes < 1
		|| config.max_queued_bytes < config.max_message_bytes || config.connect_timeout_ms < 1 || config.io_timeout_ms < 1 {
		return error('invalid WebSocket resource limits')
	}
	// Dependencies are installed only when absent, including for bare sessions.
	for name, asset in {
		'EventTarget': 'web/js/event.js'
		'URL':         'web/js/url.js'
		'TextEncoder': 'web/js/encoding.js'
		'Blob':        'web/js/blob.js'
	} {
		present := ctx.js_global(name)
		missing := present.is_undefined()
		present.free()
		if missing {
			if name == 'TextEncoder' {
				ctx.try_install_encoding_globals()!
			} else {
				value := ctx.eval_runtime_file(asset, type_module)!
				value.free()
			}
		}
	}
	global := ctx.js_global()
	defer { global.free() }
	existing := global.get('WebSocket')
	installed := !existing.is_undefined()
	existing.free()
	if installed { return }
	native := ctx.js_object()
	defer { native.free() }
	start := ctx.js_function(fn [ctx, config, mut host, ready, policy] (args []Value) Value {
		if host.closed || host.records.len >= config.max_connections {
			return ctx.js_throw(ctx.js_error(
				message: 'WebSocket connection limit reached'
				name:    'QuotaExceededError'
			))
		}
		raw := args[0].str()
		host_policy_allows_url(policy, raw) or { return ctx.js_throw(ctx.js_error(
			message: err.msg()
			name:    'SecurityError'
		)) }
		parsed := urllib.parse(raw) or { return ctx.js_throw(err.msg()) }
		if parsed.scheme !in ['ws', 'wss'] || parsed.hostname() == '' {
			return ctx.js_throw('invalid WebSocket URL')
		}
		mut command := [2]i32{}
		mut notify := [2]i32{}
		if C.vjsx_ws_pair(&command[0]) != 0 {
			return ctx.js_throw('WebSocket wake socket creation failed')
		}
		if C.vjsx_ws_pair(&notify[0]) != 0 {
			C.vjsx_ws_close(command[0])
			C.vjsx_ws_close(command[1])
			return ctx.js_throw('WebSocket notification socket creation failed')
		}
		id := host.next_id
		host.next_id++
		mut worker := &WebSocketWorker{
			config:        config
			command_read:  command[0]
			command_write: command[1]
			notify_write:  notify[1]
			ready_state:   ready.stream_ready
			id:            id
		}
		job := spawn websocket_worker(mut worker, raw, args[1].str())
		host.records[id] = WebSocketRecord{ worker: worker, callback: args[2].dup_value(), thread: job, notify_read: notify[0] }
		result := ctx.js_object()
		result.set('id', id.str())
		result.set('fd', int(notify[0]))
		return result
	})
	native.set('start', start)
	start.free()
	send := ctx.js_function(fn [ctx, mut host] (args []Value) Value {
		id := args[0].str().u64()
		record := host.records[id] or { return ctx.js_bool(false) }
		mut worker := record.worker
		kind := args[1].str()
		bytes := args[2].to_bytes()
		worker.guard.lock()
		defer { worker.guard.unlock() }
		if worker.stopped || worker.terminal { return ctx.js_bool(false) }
		if kind == 'cancel' {
			worker.cancel_requested = true
		} else {
			if worker.commands.len >= worker.config.queue_capacity || bytes.len > worker.config.max_message_bytes
				|| worker.command_bytes + bytes.len > worker.config.max_queued_bytes {
				return ctx.js_bool(false)
			}
			worker.commands << WebSocketEvent{ kind: kind, bytes: bytes, code: args[3].to_int() }
			worker.command_bytes += bytes.len
		}
		C.vjsx_ws_signal(worker.command_write)
		return ctx.js_bool(true)
	})
	native.set('send', send)
	send.free()
	drain := ctx.js_function(fn [ctx, mut host] (args []Value) Value {
		websocket_drain(ctx, mut host, args[0].str().u64()) or { return ctx.js_throw(err.msg()) }
		return ctx.js_undefined()
	})
	native.set('drain', drain)
	drain.free()
	global.set('__vjsxWebSocketNative', native)
	value := ctx.eval_runtime_file('web/js/websocket.js', type_module)!
	value.free()
	cleanup := global.get('__vjsxWebSocketCleanup')
	global.delete('__vjsxWebSocketCleanup')
	ctx.register_host_cleanup(fn [ctx, mut host, cleanup, ready] () {
		host.closed = true
		mut stream_ready := ready.stream_ready
		stream_ready.guard.lock()
		stream_ready.closed = true
		stream_ready.guard.unlock()
		result := ctx.call(cleanup) or { ctx.js_undefined() }
		result.free()
		cleanup.free()
		ids := host.records.keys()
		for id in ids { websocket_release(mut host, id) }
	})
}

fn websocket_release(mut host WebSocketHost, id u64) {
	record := host.records[id] or { return }
	mut worker := record.worker
	worker.stop()
	record.thread.wait()
	C.vjsx_ws_close(worker.command_read)
	C.vjsx_ws_close(worker.command_write)
	C.vjsx_ws_close(worker.notify_write)
	C.vjsx_ws_close(record.notify_read)
	record.callback.free()
	host.records.delete(id)
}

fn websocket_drain(ctx &Context, mut host WebSocketHost, id u64) !int {
	record := host.records[id] or { return 0 }
	mut worker := record.worker
	worker.guard.lock()
	C.vjsx_ws_drain(record.notify_read)
	events := worker.events.clone()
	worker.events = []WebSocketEvent{}
	worker.event_bytes = 0
	worker.guard.unlock()
	mut terminal := false
	for event in events {
		data := ctx.js_array_buffer(event.bytes)
		result := ctx.call(record.callback, event.kind, data, event.text, event.code, event.clean) or {
			data.free()
			websocket_release(mut host, id)
			return err
		}
		result.free()
		data.free()
		if event.kind == 'close' { terminal = true }
	}
	if terminal { websocket_release(mut host, id) }
	return events.len
}

fn (mut session RuntimeSession) drain_websocket_events() !int {
	ids := session.context.websocket_host.records.keys()
	mut count := 0
	for id in ids {
		count += websocket_drain(session.context, mut session.context.websocket_host, id)!
	}
	return count
}

pub fn (session RuntimeSession) websocket_connection_count() int {
	return session.context.websocket_host.records.len
}

fn (session RuntimeSession) pending_websocket_event_count() int {
	mut count := 0
	for _, record in session.context.websocket_host.records {
		record.worker.guard.lock()
		count += record.worker.events.len
		record.worker.guard.unlock()
	}
	return count
}
