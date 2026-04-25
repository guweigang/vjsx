module vjsx

import time

pub type RuntimeSessionNowFn = fn () i64

pub type RuntimeSessionWakeFn = fn (RuntimeSessionWakeRequest)

pub type RuntimeSessionCancelWakeFn = fn (RuntimeSessionWakeCancelRequest)

fn runtime_session_default_now() i64 {
	return time.now().unix_milli()
}

fn runtime_session_default_wake(_request RuntimeSessionWakeRequest) {}

fn runtime_session_default_cancel_wake(_request RuntimeSessionWakeCancelRequest) {}

// RuntimeSessionWakeRequest is emitted by the session when it wants the host to
// schedule a future wakeup. Hosts can ignore it when they are still relying on
// `pump_until_idle()`, or honor it once they start driving session-owned timer
// state.
pub struct RuntimeSessionWakeRequest {
pub:
	session_id string
	wake_at_ms i64
	reason     string
}

// RuntimeSessionWakeCancelRequest is emitted when the session no longer needs a
// previously requested wakeup. Hosts can use this to cancel queued wakeup work
// for the session.
pub struct RuntimeSessionWakeCancelRequest {
pub:
	session_id string
	reason     string
}

// RuntimeSessionScheduler is the host adapter that turns session wakeup
// requests into platform work, such as scheduling a lane worker task.
@[params]
pub struct RuntimeSessionScheduler {
pub:
	schedule_wakeup RuntimeSessionWakeFn       = runtime_session_default_wake
	cancel_wakeup   RuntimeSessionCancelWakeFn = runtime_session_default_cancel_wake
}

// RuntimeSessionEventLoopConfig defines the host/runtime boundary for event
// loop ownership.
//
// `runtime_owned_timers` means the embedder intends to move timer semantics
// into `RuntimeSession` instead of relying on `qjs:os.setTimeout`.
// The actual timer state machine can then live in the session while the host
// only provides time and wakeup delivery.
@[params]
pub struct RuntimeSessionEventLoopConfig {
pub:
	now_fn               RuntimeSessionNowFn        = runtime_session_default_now
	wake_fn              RuntimeSessionWakeFn       = runtime_session_default_wake
	cancel_wake_fn       RuntimeSessionCancelWakeFn = runtime_session_default_cancel_wake
	runtime_owned_timers bool
	session_id           string
}

struct RuntimeSessionEventLoopState {
mut:
	config             RuntimeSessionEventLoopConfig
	has_pending_wakeup bool
	next_wakeup_at_ms  i64 = -1
	timer_wakeup_hints map[string]i64
}

fn new_runtime_session_event_loop_state() &RuntimeSessionEventLoopState {
	return &RuntimeSessionEventLoopState{
		config:             RuntimeSessionEventLoopConfig{}
		timer_wakeup_hints: map[string]i64{}
	}
}

// Return the current time from the session's configured time source.
pub fn (session RuntimeSession) now_ms() i64 {
	return session.event_loop_state.config.now_fn()
}

// Report whether this session is intended to own timer semantics internally.
pub fn (session RuntimeSession) runtime_owns_timers() bool {
	return session.event_loop_state.config.runtime_owned_timers
}

// Replace the host/runtime event loop contract for this session.
pub fn (mut session RuntimeSession) configure_event_loop(config RuntimeSessionEventLoopConfig) {
	mut state := session.event_loop_state
	state.config = config
}

// Install the host scheduler callbacks without changing the rest of the event
// loop configuration.
pub fn (mut session RuntimeSession) set_scheduler(scheduler RuntimeSessionScheduler) {
	current := session.event_loop_state.config
	session.configure_event_loop(RuntimeSessionEventLoopConfig{
		now_fn:               current.now_fn
		wake_fn:              scheduler.schedule_wakeup
		cancel_wake_fn:       scheduler.cancel_wakeup
		runtime_owned_timers: current.runtime_owned_timers
		session_id:           current.session_id
	})
}

// Access the current event loop contract.
pub fn (session RuntimeSession) event_loop_config() RuntimeSessionEventLoopConfig {
	return session.event_loop_state.config
}

// Report whether the session has asked the host for a future wakeup.
pub fn (session RuntimeSession) has_pending_wakeup() bool {
	return session.event_loop_state.has_pending_wakeup
}

// Report whether the session already has immediate or scheduled async work that
// should cause the host to wake it up again.
pub fn (session RuntimeSession) needs_wakeup() bool {
	return session.has_ready_task() || session.has_pending_wakeup()
}

// Report the next wakeup time requested by the session.
pub fn (session RuntimeSession) next_wakeup_at() ?i64 {
	if !session.event_loop_state.has_pending_wakeup {
		return none
	}
	return session.event_loop_state.next_wakeup_at_ms
}

// Record a desired wakeup time and notify the host. This is the hook future
// runtime-owned timer semantics should use after updating session timer state.
pub fn (mut session RuntimeSession) request_wakeup_at(wake_at_ms i64, reason string) {
	mut state := session.event_loop_state
	state.has_pending_wakeup = true
	state.next_wakeup_at_ms = wake_at_ms
	state.config.wake_fn(RuntimeSessionWakeRequest{
		session_id: state.config.session_id
		wake_at_ms: wake_at_ms
		reason:     reason
	})
}

// Request the host to wake this session up after the given delay.
pub fn (mut session RuntimeSession) request_wakeup_after(delay_ms int, reason string) i64 {
	wake_at_ms := session.now_ms() + i64(delay_ms)
	session.request_wakeup_at(wake_at_ms, reason)
	return wake_at_ms
}

fn (mut session RuntimeSession) reschedule_timer_wakeup(reason string) {
	mut state := session.event_loop_state
	mut has_next := false
	mut next_wakeup_at_ms := i64(0)
	for _, wake_at_ms in state.timer_wakeup_hints {
		if !has_next || wake_at_ms < next_wakeup_at_ms {
			has_next = true
			next_wakeup_at_ms = wake_at_ms
		}
	}
	if !has_next {
		session.clear_wakeup_request()
		return
	}
	if state.has_pending_wakeup && state.next_wakeup_at_ms == next_wakeup_at_ms {
		return
	}
	session.request_wakeup_at(next_wakeup_at_ms, reason)
}

// Record a QuickJS-backed timer wakeup hint and notify the host about the
// earliest pending timer. The timer itself still belongs to QuickJS.
pub fn (mut session RuntimeSession) request_timer_wakeup_after(timer_id string, delay_ms int) i64 {
	normalized_delay_ms := if delay_ms < 0 { 0 } else { delay_ms }
	wake_at_ms := session.now_ms() + i64(normalized_delay_ms)
	mut state := session.event_loop_state
	state.timer_wakeup_hints[timer_id] = wake_at_ms
	session.reschedule_timer_wakeup('timer')
	return wake_at_ms
}

// Remove a QuickJS-backed timer wakeup hint and reschedule the host wakeup to
// the next earliest pending timer, if any.
pub fn (mut session RuntimeSession) clear_timer_wakeup(timer_id string) {
	mut state := session.event_loop_state
	if timer_id !in state.timer_wakeup_hints {
		return
	}
	state.timer_wakeup_hints.delete(timer_id)
	session.reschedule_timer_wakeup('timer-cleared')
}

// Install the JS hook used by the timer wrapper to keep wakeup hints in sync
// with QuickJS timers.
pub fn (mut session RuntimeSession) install_timer_wakeup_bridge() {
	ctx := session.context
	global := ctx.js_global()
	defer {
		global.free()
	}
	bridge := ctx.js_object()
	schedule_fn := ctx.js_function(fn [mut session, ctx] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_bool(false)
		}
		timer_id := args[0].str()
		delay_ms := args[1].to_int()
		session.request_timer_wakeup_after(timer_id, delay_ms)
		return ctx.js_bool(true)
	})
	cancel_fn := ctx.js_function(fn [mut session, ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		timer_id := args[0].str()
		session.clear_timer_wakeup(timer_id)
		return ctx.js_bool(true)
	})
	bridge.set('schedule', schedule_fn)
	bridge.set('cancel', cancel_fn)
	global.set('__vjsxRuntimeTimerWakeup', bridge)
	schedule_fn.free()
	cancel_fn.free()
	bridge.free()
}

// Report whether the session already has ready work in the QuickJS job queue.
// This plural form is a readability alias for `has_ready_task()`.
pub fn (session RuntimeSession) has_ready_tasks() bool {
	return session.has_ready_task()
}

// Clear any previously requested host wakeup.
pub fn (mut session RuntimeSession) clear_wakeup_request() {
	mut state := session.event_loop_state
	if state.has_pending_wakeup {
		state.config.cancel_wake_fn(RuntimeSessionWakeCancelRequest{
			session_id: state.config.session_id
			reason:     'cleared'
		})
	}
	state.has_pending_wakeup = false
	state.next_wakeup_at_ms = -1
}
