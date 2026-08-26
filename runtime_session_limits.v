module vjsx

pub const default_runtime_session_max_diagnostics = 128
pub const default_runtime_session_max_timer_wakeup_hints = 0
pub const default_runtime_session_max_observations = 256

// RuntimeEngineLimits configures limits enforced by QuickJS itself. Zero leaves
// a current engine memory/stack/GC value unchanged. A zero turn timeout disables
// the default per-turn deadline.
@[params]
pub struct RuntimeEngineLimits {
pub:
	memory_limit_bytes      usize
	max_stack_size_bytes    usize
	gc_threshold_bytes      usize
	default_turn_timeout_ms u64
}

@[params]
pub struct RuntimeSessionLimits {
pub:
	max_diagnostics int = default_runtime_session_max_diagnostics
	// Zero means unlimited. This limit only applies to vjsx wakeup hints, not
	// the underlying QuickJS timer queue.
	max_timer_wakeup_hints int = default_runtime_session_max_timer_wakeup_hints
	max_observations       int = default_runtime_session_max_observations
}

struct RuntimeSessionLimitState {
mut:
	config                      RuntimeSessionLimits = RuntimeSessionLimits{}
	dropped_diagnostics         int
	rejected_timer_wakeup_hints int
	dropped_observations        int
	engine                      RuntimeEngineLimits
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

// Configure limits that QuickJS enforces for this session. Engine limits are
// applied immediately and should normally be set before loading user code.
pub fn (mut session RuntimeSession) configure_engine_limits(limits RuntimeEngineLimits) {
	if session.closed || session.is_running() {
		return
	}
	mut state := session.limit_state
	state.engine = limits
	if limits.memory_limit_bytes > 0 {
		session.runtime.set_memory_limit_bytes(limits.memory_limit_bytes)
	}
	if limits.max_stack_size_bytes > 0 {
		session.runtime.set_max_stack_size_bytes(limits.max_stack_size_bytes)
	}
	if limits.gc_threshold_bytes > 0 {
		session.runtime.set_gc_threshold_bytes(limits.gc_threshold_bytes)
	}
}

pub fn (session RuntimeSession) engine_limits() RuntimeEngineLimits {
	return session.limit_state.engine
}

pub fn (session RuntimeSession) dropped_observation_count() int {
	return session.limit_state.dropped_observations
}
