module vjsx

import net
import net.http
import sync
import json2
import time
import crypto.sha1
import encoding.base64

// HTTP/1.1 compatibility subset: bounded buffered request/response bodies,
// close-delimited responses and raw upgrade sockets. Chunked requests return
// 501; TLS server options and streaming response APIs are not advertised.
// Socket.acceptWebSocket is a native vjsx extension, not a Node API.
// Listener and connection workers contain native data only. Their notifications,
// bounded queues and lifetime are owned by the existing WebSocket host stream.
@[heap]
struct HttpListener {
	guard    &sync.Mutex = sync.new_mutex()
	worker   &WebSocketWorker
	listener &net.TcpListener
mut:
	pending map[int]&net.TcpConn
	next_id int = 1
}

struct HttpRequestHead {
	method         string
	url            string
	headers        map[string]string
	remote_address string
}

fn http_server_record(ctx &Context, mut host WebSocketHost) !(&WebSocketWorker, int) {
	if host.closed || host.records.len >= 128 { return error('HTTP host connection limit reached') }
	mut command := [2]i32{}
	mut notify := [2]i32{}
	if C.vjsx_ws_pair(&command[0]) != 0 { return error('HTTP command socket creation failed') }
	if C.vjsx_ws_pair(&notify[0]) != 0 {
		C.vjsx_ws_close(command[0])
		C.vjsx_ws_close(command[1])
		return error('HTTP notification socket creation failed')
	}
	id := host.next_id
	host.next_id++
	worker := &WebSocketWorker{
		config:        WebSocketConfig{ max_message_bytes: 1048576, max_queued_bytes: 4194304 }
		command_read:  command[0]
		command_write: command[1]
		notify_write:  notify[1]
		ready_state:   ctx.host_cleanup_state.host_async.stream_ready
		id:            id
	}
	return worker, int(notify[0])
}

fn http_listener_run(mut listener HttpListener) {
	mut worker := listener.worker
	defer {
		listener.listener.close() or {}
		listener.guard.lock()
		for _, mut conn in listener.pending { conn.close() or {} }
		listener.pending.clear()
		listener.guard.unlock()
		worker.emit(WebSocketEvent{ kind: 'close', code: 1000, clean: true })
	}
	for {
		ready := C.vjsx_ws_wait(listener.listener.sock.handle, worker.command_read, 0, -1)
		worker.guard.lock()
		stopped := worker.stopped || worker.cancel_requested
		C.vjsx_ws_drain(worker.command_read)
		worker.guard.unlock()
		if stopped || ready < 0 { return }
		if ready & 1 == 0 { continue }
		mut conn := listener.listener.accept() or { continue }
		listener.guard.lock()
		if listener.pending.len >= 64 {
			listener.guard.unlock()
			conn.close() or {}
			continue
		}
		id := listener.next_id
		listener.next_id++
		listener.pending[id] = conn
		listener.guard.unlock()
		if !worker.emit(WebSocketEvent{ kind: 'accept', code: id }) { return }
	}
}

fn http_server_frame(opcode u8, payload []u8) []u8 {
	mut frame := [u8(0x80) | opcode]
	if payload.len < 126 {
		frame << u8(payload.len)
	} else if payload.len <= 65535 {
		frame << [u8(126), u8(payload.len >> 8), u8(payload.len)]
	} else {
		frame << u8(127)
		for shift := 56; shift >= 0; shift -= 8 { frame << u8(u64(payload.len) >> shift) }
	}
	frame << payload
	return frame
}

fn http_connection_run(mut worker WebSocketWorker, conn &net.TcpConn) {
	mut io := WebSocketIO{ tcp: conn, worker: worker, wake: worker.command_read, timeout_ms: 10000 }
	C.vjsx_ws_nonblock(conn.sock.handle)
	defer {
		io.dispose()
		worker.emit(WebSocketEvent{ kind: 'close', code: 1006 })
	}
	http_connection_serve(mut worker, mut io) or {
		worker.guard.lock()
		stopped := worker.stopped
		worker.guard.unlock()
		if !stopped { worker.emit(WebSocketEvent{ kind: 'error', text: err.msg() }) }
	}
}

fn http_connection_serve(mut worker WebSocketWorker, mut io WebSocketIO) ! {
	mut incoming := []u8{}
	mut buffer := []u8{len: 16384}
	deadline := time.now().unix_milli() + 10000
	mut end := -1
	for end < 0 {
		n := io.read(mut buffer, deadline)!
		if n <= 0 { return }
		incoming << buffer[..n]
		end = incoming.bytestr().index('\r\n\r\n') or { -1 }
		if (end < 0 && incoming.len > 16384) || end > 16384 {
			return error('HTTP headers too large')
		}
	}
	request := http.parse_request_head_str(incoming[..end + 4].bytestr())!
	mut headers := map[string]string{}
	for key in request.header.keys() {
		values := request.header.custom_values(key)
		lowered := key.to_lower()
		if lowered in ['content-length', 'transfer-encoding', 'host', 'sec-websocket-key',
			'sec-websocket-version'] && values.len != 1 {
			return error('Ambiguous HTTP framing header')
		}
		headers[lowered] = values.join(', ')
	}
	if headers['transfer-encoding'] != '' {
		io.write('HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'.bytes())!
		return
	}
	raw_length := headers['content-length']
	if raw_length != '' && (raw_length.len > 7 || raw_length.bytes().any(it < `0` || it > `9`)) {
		return error('Invalid Content-Length')
	}
	length := raw_length.int()
	if length > 1048576 { return error('HTTP body too large') }
	mut body := incoming[end + 4..].clone()
	upgrade := headers['upgrade'] != '' && 'upgrade' in headers['connection'].to_lower().split(',').map(it.trim_space())
	if !upgrade {
		for body.len < length {
			n := io.read(mut buffer, deadline)!
			if n <= 0 { return error('Truncated HTTP body') }
			body << buffer[..n]
		}
		body = body[..length].clone()
	}
	peer := io.tcp.peer_addr()!.str()
	head := json2.encode(HttpRequestHead{ method: request.method.str(), url: request.url, headers: headers, remote_address: peer },
		escape_unicode: true
		time_as_unix:   true
	)
	if !worker.emit(WebSocketEvent{ kind: if upgrade { 'upgrade' } else { 'request' }, bytes: body, text: head }) {
		return
	}
	incoming = if upgrade { body.clone() } else { []u8{} }
	mut websocket := false
	mut raw_mode := false
	mut closing := false
	mut close_deadline := i64(0)
	mut decoder := WebSocketFrameDecoder{ max_message_bytes: 1048576, expect_mask: true }
	for {
		worker.guard.lock()
		commands := worker.commands.clone()
		worker.commands.clear()
		worker.command_bytes = 0
		stopped := worker.stopped || worker.cancel_requested
		C.vjsx_ws_drain(worker.command_read)
		worker.guard.unlock()
		if stopped { return }
		for command in commands {
			match command.kind {
				'write', 'end' {
					io.write(command.bytes)!
					// upgrade head was already handed to the JS listener.
					if upgrade && !raw_mode { incoming = []u8{} }
					raw_mode = upgrade
					if command.kind == 'end' { return }
				}
				'websocket' {
					key := headers['sec-websocket-key']
					decoded := base64.decode(key)
					if !upgrade || headers['upgrade'].to_lower() != 'websocket' || request.method != .get || request.version != .v1_1 || decoded.len != 16 || base64.encode(decoded) != key
						|| headers['sec-websocket-version'] != '13' || 'upgrade' !in headers['connection'].to_lower().split(',').map(it.trim_space()) {
						return error('Invalid WebSocket handshake')
					}
					accept := base64.encode(sha1.sum((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').bytes()))
					io.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n'.bytes())!
					websocket = true
					if !worker.emit(WebSocketEvent{ kind: 'open' }) { return }
				}
				'text', 'binary' {
					if !websocket { return error('WebSocket not upgraded') }
					io.write(http_server_frame(if command.kind == 'text' { 1 } else { 2 }, command.bytes))!
				}
				'close' {
					if websocket {
						mut payload := [u8(command.code >> 8), u8(command.code)]
						payload << command.bytes
						io.write(http_server_frame(8, payload))!
					}
					if !websocket { return }
					closing = true
					close_deadline = time.now().unix_milli() + 1000
				}
				else { return error('Invalid HTTP socket command') }
			}
		}
		if websocket {
			for {
				frame := decoder.decode(mut incoming)
				if frame.kind == .need_more { break }
				if frame.kind == .failure {
					io.write(http_server_frame(8, [u8(frame.close_code >> 8), u8(frame.close_code)]))!
					return error(frame.reason)
				}
				if frame.kind == .message && !closing {
					if !worker.emit(WebSocketEvent{
						kind:  if frame.opcode == .text {
							'text'
						} else {
							'binary'
						}
						bytes: frame.payload.clone()
					}) {
						return
					}
				} else if frame.kind == .control {
					if frame.opcode == .ping { io.write(http_server_frame(10, frame.payload))! }
					if frame.opcode == .close {
						if !closing { io.write(http_server_frame(8, frame.payload))! }
						code := if frame.payload.len >= 2 {
							(int(frame.payload[0]) << 8) | int(frame.payload[1])
						} else {
							1000
						}
						worker.emit(WebSocketEvent{ kind: 'close', code: code, clean: true })
						return
					}
				}
				incoming = incoming[frame.consumed..].clone()
			}
		} else if raw_mode && incoming.len > 0 {
			if !worker.emit(WebSocketEvent{ kind: 'data', bytes: incoming }) { return }
			incoming = []u8{}
		}
		ready := C.vjsx_ws_wait(if websocket || raw_mode { io.tcp.sock.handle } else { -1 }, worker.command_read, 0, if closing {
			left := int(close_deadline - time.now().unix_milli())
			if left <= 0 { return }
			left
		} else if websocket || raw_mode {
			-1
		} else {
			30000
		})
		if ready == 0 && closing { return }
		if ready < 0 || ready == 0 { return error('HTTP response deadline exceeded') }
		if ready & 1 != 0 {
			n := C.vjsx_ws_plain_io(io.tcp.sock.handle, buffer.data, buffer.len, 0)
			if n == 0 { return }
			if n == -2 { continue }
			if n < 0 { return error('HTTP socket read failed') }
			incoming << buffer[..n]
			if incoming.len > 1048590 { return error('HTTP socket input limit reached') }
		}
	}
}

fn (ctx &Context) http_server_exports(policy HostPolicy) !Value {
	// Installs the existing stream cleanup even for explicitly installed HTTP modules.
	ctx.try_install_websocket_globals_policy(WebSocketConfig{}, policy)!
	mut host := ctx.websocket_host
	mut listeners := &HttpListenerRegistry{}
	native := ctx.js_object()
	start := ctx.js_function(fn [ctx, mut host, mut listeners, policy] (args []Value) Value {
		address := args[0].str()
		port := args[1].to_int()
		if port < 0 || port > 65535 { return ctx.js_throw('Invalid HTTP listen port') }
		host_policy_allows_url(policy, 'http://${address}:${port}') or {
			return ctx.js_throw(ctx.js_error(
				message: err.msg()
				name:    'SecurityError'
			))
		}
		if listeners.items.len >= 16 { return ctx.js_throw('HTTP listener limit reached') }
		mut listener := net.listen_tcp(.ip, '${address}:${port}') or {
			return ctx.js_throw(ctx.js_error(
				message: err.msg()
				name:    'Error'
			))
		}
		worker, fd := http_server_record(ctx, mut host) or {
			listener.close() or {}
			return ctx.js_throw(err.msg())
		}
		actual := listener.addr() or {
			listener.close() or {}
			return ctx.js_throw(err.msg())
		}
		mut state := &HttpListener{ worker: worker, listener: listener }
		job := spawn http_listener_run(mut state)
		host.records[worker.id] = WebSocketRecord{ worker: worker, callback: args[2].dup_value(), thread: job, notify_read: fd }
		listeners.items[worker.id] = state
		result := ctx.js_object()
		result.set('id', worker.id.str())
		result.set('fd', fd)
		result.set('port', int(actual.port() or { 0 }))
		return result
	})
	native.set('listen', start)
	start.free()
	connection := ctx.js_function(fn [ctx, mut host, mut listeners] (args []Value) Value {
		mut state := listeners.items[args[0].str().u64()] or { return ctx.js_throw('HTTP listener is closed') }
		mut listener := state
		listener.guard.lock()
		mut conn := listener.pending[args[1].to_int()] or {
			listener.guard.unlock()
			return ctx.js_throw('HTTP connection is closed')
		}
		listener.pending.delete(args[1].to_int())
		listener.guard.unlock()
		connection_worker, fd := http_server_record(ctx, mut host) or {
			mut c := conn
			c.close() or {}
			return ctx.js_throw(err.msg())
		}
		mut worker := unsafe { connection_worker }
		job := spawn http_connection_run(mut worker, conn)
		host.records[worker.id] = WebSocketRecord{ worker: worker, callback: args[2].dup_value(), thread: job, notify_read: fd }
		result := ctx.js_object()
		result.set('id', worker.id.str())
		result.set('fd', fd)
		return result
	})
	native.set('connection', connection)
	connection.free()
	send := ctx.js_function(fn [ctx, mut host] (args []Value) Value {
		record := host.records[args[0].str().u64()] or { return ctx.js_bool(false) }
		mut worker := record.worker
		bytes := args[2].to_bytes()
		worker.guard.lock()
		defer { worker.guard.unlock() }
		if worker.stopped || worker.terminal || worker.commands.len >= 64 || bytes.len > 1048576 || worker.command_bytes + bytes.len > 4194304 {
			return ctx.js_bool(false)
		}
		worker.commands << WebSocketEvent{ kind: args[1].str(), bytes: bytes, code: args[3].to_int() }
		worker.command_bytes += bytes.len
		C.vjsx_ws_signal(worker.command_write)
		return ctx.js_bool(true)
	})
	native.set('send', send)
	send.free()
	stop := ctx.js_function(fn [ctx, mut host] (args []Value) Value {
		id := args[0].str().u64()
		if record := host.records[id] {
			mut worker := record.worker
			worker.guard.lock()
			worker.cancel_requested = true
			C.vjsx_ws_signal(worker.command_write)
			worker.guard.unlock()
		}
		return ctx.js_undefined()
	})
	forget := ctx.js_function(fn [ctx, mut listeners] (args []Value) Value {
		listeners.items.delete(args[0].str().u64())
		return ctx.js_undefined()
	})
	native.set('forget', forget)
	forget.free()
	native.set('stop', stop)
	stop.free()
	drain := ctx.js_function(fn [ctx, mut host, mut listeners] (args []Value) Value {
		websocket_drain(ctx, mut host, args[0].str().u64()) or { return ctx.js_throw(err.msg()) }
		if args[0].str().u64() !in host.records { listeners.items.delete(args[0].str().u64()) }
		return ctx.js_undefined()
	})
	native.set('drain', drain)
	drain.free()
	global := ctx.js_global()
	global.set('__vjsxHttpServerNative', native)
	native.free()
	value := ctx.eval_runtime_file('web/js/http_server.js', type_module)!
	value.free()
	exports := global.get('__vjsxHttpServerExports')
	global.delete('__vjsxHttpServerExports')
	cleanup := global.get('__vjsxHttpServerCleanup')
	global.delete('__vjsxHttpServerCleanup')
	global.free()
	ctx.register_host_cleanup(fn [ctx, cleanup] () {
		result := ctx.call(cleanup) or { ctx.js_undefined() }
		result.free()
		cleanup.free()
	})
	return exports
}

@[heap]
struct HttpListenerRegistry {
mut:
	items map[u64]&HttpListener
}
