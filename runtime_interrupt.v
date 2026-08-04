module vjsx

import time

// RuntimeInterruptReason identifies why QuickJS execution was interrupted.
pub enum RuntimeInterruptReason {
	none
	cancelled
	deadline
}

// RuntimeInterruptedError is returned when cooperative QuickJS interruption
// stops JavaScript execution. A runtime that returns this error is poisoned and
// must be closed rather than reused.
pub struct RuntimeInterruptedError {
	Error
pub:
	reason RuntimeInterruptReason
}

pub fn (err &RuntimeInterruptedError) msg() string {
	return match err.reason {
		.cancelled { 'QuickJS execution cancelled; runtime is no longer reusable' }
		.deadline { 'QuickJS execution deadline exceeded; runtime is no longer reusable' }
		.none { 'QuickJS execution interrupted; runtime is no longer reusable' }
	}
}

fn (rt Runtime) interrupt_reason() RuntimeInterruptReason {
	return match C.vjsx_interrupt_reason(rt.interrupt_state) {
		1 { .cancelled }
		2 { .deadline }
		else { .none }
	}
}

fn (rt Runtime) ensure_executable() ! {
	reason := rt.interrupt_reason()
	if reason != .none {
		return &RuntimeInterruptedError{
			reason: reason
		}
	}
}

fn (rt Runtime) set_deadline_after_ms(delay_ms u64) {
	C.vjsx_interrupt_set_deadline_after_ms(rt.interrupt_state, delay_ms)
}

fn (rt Runtime) clear_deadline() {
	C.vjsx_interrupt_clear_deadline(rt.interrupt_state)
}

fn (rt Runtime) cancel() {
	C.vjsx_interrupt_cancel(rt.interrupt_state)
}

// Set an absolute execution deadline. The wall-clock delta is converted here;
// the interrupt handler itself measures elapsed time with a monotonic clock.
pub fn (session RuntimeSession) set_deadline(deadline time.Time) {
	if session.closed {
		return
	}
	now_ms := time.now().unix_milli()
	deadline_ms := deadline.unix_milli()
	delay_ms := if deadline_ms > now_ms { u64(deadline_ms - now_ms) } else { u64(0) }
	session.runtime.set_deadline_after_ms(delay_ms)
}

// Clear a pending deadline. Once interrupted, a session stays poisoned and
// this operation intentionally cannot make it reusable.
pub fn (session RuntimeSession) clear_deadline() {
	if session.closed {
		return
	}
	session.runtime.clear_deadline()
}

// Request cancellation. This only performs an atomic store and is safe to call
// from another thread while QuickJS is executing.
pub fn (session RuntimeSession) cancel() {
	if session.closed {
		return
	}
	session.runtime.cancel()
}

// Return the interruption reason, or `none` while the session is usable.
pub fn (session RuntimeSession) interrupt_reason() RuntimeInterruptReason {
	if session.closed {
		return .none
	}
	return session.runtime.interrupt_reason()
}

// Report whether execution was interrupted and the session must be closed.
pub fn (session RuntimeSession) is_interrupted() bool {
	return session.interrupt_reason() != .none
}
