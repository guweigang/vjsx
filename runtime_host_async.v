module vjsx

import sync

pub type RuntimeHostAsyncReadyFn = fn (RuntimeHostAsyncReadyRequest)

fn runtime_host_async_default_ready(_request RuntimeHostAsyncReadyRequest) {}

// RuntimeHostAsyncReadyRequest tells a host scheduler that a plain completion
// event is waiting for delivery on the owning lane.
pub struct RuntimeHostAsyncReadyRequest {
pub:
	session_id   string
	operation_id u64
}

pub enum RuntimeHostAsyncOutcome {
	resolve
	reject
	cancelled
	timed_out
	closed
}

// RuntimeHostAsyncCompletion carries only V-owned data. It is deliberately
// unable to contain a Context or Value, so worker threads cannot touch QuickJS.
pub struct RuntimeHostAsyncCompletion {
pub:
	outcome    RuntimeHostAsyncOutcome
	text       string
	bytes      []u8
	is_binary  bool
	error_name string
}

@[params]
pub struct RuntimeHostAsyncOptions {
pub:
	kind       string = 'host_async'
	timeout_ms int
}

struct RuntimeHostAsyncCancelState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	cancelled bool
	reason    string
}

// RuntimeHostAsyncCancelToken is safe for worker threads. It contains no JS
// state and becomes cancelled when cancellation, timeout, or session close wins.
pub struct RuntimeHostAsyncCancelToken {
	state &RuntimeHostAsyncCancelState
}

pub fn (token RuntimeHostAsyncCancelToken) is_cancelled() bool {
	mut state := token.state
	state.guard.lock()
	cancelled := state.cancelled
	state.guard.unlock()
	return cancelled
}

pub fn (token RuntimeHostAsyncCancelToken) reason() string {
	mut state := token.state
	state.guard.lock()
	reason := state.reason
	state.guard.unlock()
	return reason
}

fn (token RuntimeHostAsyncCancelToken) mark_cancelled(reason string) {
	mut state := token.state
	state.guard.lock()
	if !state.cancelled {
		state.cancelled = true
		state.reason = reason
	}
	state.guard.unlock()
}

struct RuntimeHostAsyncRecord {
	id          u64
	kind        string
	deadline_ms i64 = -1
	resolve     Value
	reject      Value
	token       RuntimeHostAsyncCancelToken
}

struct RuntimeHostAsyncQueuedEvent {
	id         u64
	completion RuntimeHostAsyncCompletion
}

struct RuntimeHostAsyncState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	next_id    u64 = 1
	operations map[u64]RuntimeHostAsyncRecord
	queued     []RuntimeHostAsyncQueuedEvent
	terminal   map[u64]bool
	closed     bool
	session_id string
	ready_fn   RuntimeHostAsyncReadyFn = runtime_host_async_default_ready
}

fn new_runtime_host_async_state() &RuntimeHostAsyncState {
	return &RuntimeHostAsyncState{
		operations: map[u64]RuntimeHostAsyncRecord{}
		queued: []RuntimeHostAsyncQueuedEvent{}
		terminal: map[u64]bool{}
	}
}

// RuntimeHostAsyncCompletionPort is the only object a worker needs. Submitting
// a completion only appends plain V data to the session queue; it never calls JS.
pub struct RuntimeHostAsyncCompletionPort {
	operation_id u64
	state        &RuntimeHostAsyncState
	token        RuntimeHostAsyncCancelToken
}

fn (port RuntimeHostAsyncCompletionPort) submit(completion RuntimeHostAsyncCompletion) bool {
	mut state := port.state
	state.guard.lock()
	if state.closed || port.operation_id !in state.operations || state.terminal[port.operation_id] {
		state.guard.unlock()
		return false
	}
	state.terminal[port.operation_id] = true
	state.queued << RuntimeHostAsyncQueuedEvent{
		id: port.operation_id
		completion: completion
	}
	ready_fn := state.ready_fn
	session_id := state.session_id
	state.guard.unlock()
	if completion.outcome != .resolve && completion.outcome != .reject {
		port.token.mark_cancelled(completion.text)
	}
	ready_fn(RuntimeHostAsyncReadyRequest{
		session_id: session_id
		operation_id: port.operation_id
	})
	return true
}

pub fn (port RuntimeHostAsyncCompletionPort) resolve_text(text string) bool {
	return port.submit(RuntimeHostAsyncCompletion{ outcome: .resolve, text: text })
}

pub fn (port RuntimeHostAsyncCompletionPort) resolve_bytes(bytes []u8) bool {
	return port.submit(RuntimeHostAsyncCompletion{
		outcome: .resolve
		bytes: bytes.clone()
		is_binary: true
	})
}

pub fn (port RuntimeHostAsyncCompletionPort) reject(message string) bool {
	return port.submit(RuntimeHostAsyncCompletion{
		outcome: .reject
		text: message
		error_name: 'Error'
	})
}

pub fn (port RuntimeHostAsyncCompletionPort) cancel(reason string) bool {
	return port.submit(RuntimeHostAsyncCompletion{
		outcome: .cancelled
		text: if reason == '' { 'This operation was aborted' } else { reason }
		error_name: 'AbortError'
	})
}

pub struct RuntimeHostAsyncOperation {
pub:
	id         u64
	promise    Value
	completion RuntimeHostAsyncCompletionPort
	cancel     RuntimeHostAsyncCancelToken
}

// Bind an AbortSignal-compatible object to this operation. The listener runs
// on the JS/session lane and forwards cancellation through the same terminal
// race gate as worker completion and timeout. It is removed on settlement.
pub fn (operation RuntimeHostAsyncOperation) bind_abort_signal(signal Value) ! {
	ctx := &operation.promise.ctx
	helper := ctx.eval('(signal, promise) => {
		if (signal == null || typeof signal.addEventListener !== "function") {
			throw new TypeError("signal must be an AbortSignal");
		}
		const cancel = () => {
			const reason = signal.reason;
			promise.__vjsxCancel(reason?.message ?? String(reason ?? "This operation was aborted"));
		};
		if (signal.aborted) {
			cancel();
			return;
		}
		signal.addEventListener("abort", cancel, { once: true });
		const cleanup = () => signal.removeEventListener("abort", cancel);
		promise.then(cleanup, cleanup);
	}')!
	defer {
		helper.free()
	}
	result := ctx.call(helper, signal, operation.promise)!
	result.free()
}

// Start a host operation on the session-owning lane. The returned Promise is
// caller-owned. Resolve/reject functions stay session-owned until one terminal
// event wins or the session closes.
pub fn (mut session RuntimeSession) start_host_async_operation(options RuntimeHostAsyncOptions) !RuntimeHostAsyncOperation {
	if session.is_closed() || session.phase() in [.draining, .poisoned, .closed] {
		return error('runtime session is not accepting host operations')
	}
	capability := session.context.js_promise_capability()
	token := RuntimeHostAsyncCancelToken{
		state: &RuntimeHostAsyncCancelState{}
	}
	mut state := session.host_async_state
	state.guard.lock()
	id := state.next_id
	state.next_id++
	state.operations[id] = RuntimeHostAsyncRecord{
		id: id
		kind: options.kind
		deadline_ms: if options.timeout_ms > 0 {
			session.now_ms() + i64(options.timeout_ms)
		} else {
			i64(-1)
		}
		resolve: capability.resolve
		reject: capability.reject
		token: token
	}
	state.guard.unlock()
	cancel_fn := session.context.js_function(fn [mut session, id] (args []Value) Value {
		reason := if args.len > 0 && args[0].is_string() {
			args[0].str()
		} else {
			'This operation was aborted'
		}
		return session.context.js_bool(session.cancel_host_async_operation(id, reason))
	})
	capability.promise.set('__vjsxCancel', cancel_fn)
	cancel_fn.free()
	if options.timeout_ms > 0 {
		session.reschedule_host_async_wakeup('host-async-timeout')
	}
	port := RuntimeHostAsyncCompletionPort{
		operation_id: id
		state: state
		token: token
	}
	return RuntimeHostAsyncOperation{
		id: id
		promise: capability.promise
		completion: port
		cancel: token
	}
}

// Cancel an operation from the owning lane (for example from an AbortSignal
// listener). Completion, cancellation, timeout, and close race through the same
// first-terminal-event gate.
pub fn (mut session RuntimeSession) cancel_host_async_operation(id u64, reason string) bool {
	mut state := session.host_async_state
	state.guard.lock()
	record := state.operations[id] or {
		state.guard.unlock()
		return false
	}
	state.guard.unlock()
	real_port := RuntimeHostAsyncCompletionPort{
		operation_id: id
		state: session.host_async_state
		token: record.token
	}
	return real_port.cancel(reason)
}

fn (mut session RuntimeSession) enqueue_due_host_async_timeouts() {
	now := session.now_ms()
	mut state := session.host_async_state
	state.guard.lock()
	for id, record in state.operations {
		if record.deadline_ms >= 0 && record.deadline_ms <= now && !state.terminal[id] {
			state.terminal[id] = true
			record.token.mark_cancelled('host operation timed out')
			state.queued << RuntimeHostAsyncQueuedEvent{
				id: id
				completion: RuntimeHostAsyncCompletion{
					outcome: .timed_out
					text: 'host operation timed out'
					error_name: 'TimeoutError'
				}
			}
		}
	}
	state.guard.unlock()
}

// Settle queued host events. This must only be called by the session owner.
// JS Values are constructed and Promise callbacks invoked exclusively here.
fn (mut session RuntimeSession) settle_host_async_record(record RuntimeHostAsyncRecord, completion RuntimeHostAsyncCompletion) ! {
	value := if completion.outcome == .resolve {
		if completion.is_binary {
			session.context.js_array_buffer(completion.bytes)
		} else {
			session.context.js_string(completion.text)
		}
	} else {
		session.context.js_error(
			message: completion.text
			name: if completion.error_name == '' { 'Error' } else { completion.error_name }
		)
	}
	callback := if completion.outcome == .resolve { record.resolve } else { record.reject }
	call_result := session.context.call(callback, value) or {
		value.free()
		record.resolve.free()
		record.reject.free()
		session.record_runtime_error('host_async_${record.kind}', err.msg())
		return err
	}
	call_result.free()
	value.free()
	record.resolve.free()
	record.reject.free()
}

pub fn (mut session RuntimeSession) drain_host_async_events() !int {
	if session.is_closed() {
		return 0
	}
	session.enqueue_due_host_async_timeouts()
	mut state := session.host_async_state
	state.guard.lock()
	events := state.queued.clone()
	state.queued = []RuntimeHostAsyncQueuedEvent{}
	state.guard.unlock()
	mut settled := 0
	for event in events {
		state.guard.lock()
		record := state.operations[event.id] or {
			state.guard.unlock()
			continue
		}
		state.operations.delete(event.id)
		state.terminal.delete(event.id)
		state.guard.unlock()
		session.settle_host_async_record(record, event.completion)!
		settled++
	}
	session.reschedule_host_async_wakeup('host-async')
	return settled
}

fn (mut session RuntimeSession) close_host_async_operations() {
	session.enqueue_due_host_async_timeouts()
	mut state := session.host_async_state
	state.guard.lock()
	if state.closed {
		state.guard.unlock()
		return
	}
	state.closed = true
	records := state.operations.values()
	queued := state.queued.clone()
	state.operations = map[u64]RuntimeHostAsyncRecord{}
	state.queued = []RuntimeHostAsyncQueuedEvent{}
	state.terminal = map[u64]bool{}
	state.guard.unlock()
	mut terminal_events := map[u64]RuntimeHostAsyncCompletion{}
	for event in queued {
		terminal_events[event.id] = event.completion
	}
	for record in records {
		completion := terminal_events[record.id] or {
			record.token.mark_cancelled('runtime session closed')
			RuntimeHostAsyncCompletion{
				outcome: .closed
				text: 'runtime session closed'
				error_name: 'SessionClosedError'
			}
		}
		session.settle_host_async_record(record, completion) or {}
	}
}

pub fn (session RuntimeSession) pending_host_async_operation_count() int {
	mut state := session.host_async_state
	state.guard.lock()
	count := state.operations.len
	state.guard.unlock()
	return count
}

pub fn (session RuntimeSession) pending_host_async_event_count() int {
	mut state := session.host_async_state
	state.guard.lock()
	count := state.queued.len
	state.guard.unlock()
	return count
}

fn (mut session RuntimeSession) configure_host_async_ready(session_id string, ready_fn RuntimeHostAsyncReadyFn) {
	mut state := session.host_async_state
	state.guard.lock()
	state.session_id = session_id
	state.ready_fn = ready_fn
	state.guard.unlock()
}

fn (session RuntimeSession) next_host_async_deadline() ?i64 {
	mut state := session.host_async_state
	state.guard.lock()
	mut found := false
	mut deadline := i64(0)
	for id, record in state.operations {
		if record.deadline_ms >= 0 && !state.terminal[id]
			&& (!found || record.deadline_ms < deadline) {
			found = true
			deadline = record.deadline_ms
		}
	}
	state.guard.unlock()
	if !found {
		return none
	}
	return deadline
}
