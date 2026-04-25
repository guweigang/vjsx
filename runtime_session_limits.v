module vjsx

pub const default_runtime_session_max_diagnostics = 128
pub const default_runtime_session_max_timer_wakeup_hints = 0

@[params]
pub struct RuntimeSessionLimits {
pub:
	max_diagnostics int = default_runtime_session_max_diagnostics
	// Zero means unlimited. This limit only applies to vjsx wakeup hints, not
	// the underlying QuickJS timer queue.
	max_timer_wakeup_hints int = default_runtime_session_max_timer_wakeup_hints
}

struct RuntimeSessionLimitState {
mut:
	config                      RuntimeSessionLimits = RuntimeSessionLimits{}
	dropped_diagnostics         int
	rejected_timer_wakeup_hints int
}

fn new_runtime_session_limit_state() &RuntimeSessionLimitState {
	return &RuntimeSessionLimitState{
		config: RuntimeSessionLimits{}
	}
}

pub fn (mut session RuntimeSession) configure_limits(limits RuntimeSessionLimits) {
	if session.closed {
		return
	}
	mut state := session.limit_state
	state.config = limits
}

pub fn (session RuntimeSession) limits() RuntimeSessionLimits {
	return session.limit_state.config
}

pub fn (session RuntimeSession) dropped_diagnostic_count() int {
	return session.limit_state.dropped_diagnostics
}

pub fn (session RuntimeSession) rejected_timer_wakeup_hint_count() int {
	return session.limit_state.rejected_timer_wakeup_hints
}
