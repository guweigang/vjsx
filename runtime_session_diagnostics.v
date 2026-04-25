module vjsx

pub type RuntimeSessionDiagnosticHandler = fn (RuntimeSessionDiagnostic)

fn runtime_session_default_diagnostic_handler(_diagnostic RuntimeSessionDiagnostic) {}

pub struct RuntimeSessionDiagnostic {
pub:
	session_id        string
	kind              string
	message           string
	wakeup_generation u64
	at_ms             i64
}

struct RuntimeSessionDiagnosticState {
mut:
	errors  []RuntimeSessionDiagnostic
	handler RuntimeSessionDiagnosticHandler = runtime_session_default_diagnostic_handler
}

fn new_runtime_session_diagnostic_state() &RuntimeSessionDiagnosticState {
	return &RuntimeSessionDiagnosticState{
		errors: []RuntimeSessionDiagnostic{}
	}
}

fn (session RuntimeSession) record_runtime_error(kind string, message string) {
	if session.closed || session.event_loop_state.closed {
		return
	}
	mut state := session.diagnostic_state
	diagnostic := RuntimeSessionDiagnostic{
		session_id:        session.event_loop_state.config.session_id
		kind:              kind
		message:           message
		wakeup_generation: session.wakeup_generation()
		at_ms:             session.now_ms()
	}
	max_diagnostics := session.limit_state.config.max_diagnostics
	if max_diagnostics > 0 && state.errors.len >= max_diagnostics {
		state.errors.delete(0)
		mut limit_state := session.limit_state
		limit_state.dropped_diagnostics++
	}
	state.errors << diagnostic
	state.handler(diagnostic)
}

pub fn (session RuntimeSession) diagnostics() []RuntimeSessionDiagnostic {
	return session.diagnostic_state.errors.clone()
}

pub fn (session RuntimeSession) last_diagnostic() ?RuntimeSessionDiagnostic {
	if session.diagnostic_state.errors.len == 0 {
		return none
	}
	return session.diagnostic_state.errors[session.diagnostic_state.errors.len - 1]
}

pub fn (session RuntimeSession) diagnostic_error_count() int {
	return session.diagnostic_state.errors.len
}

pub fn (session RuntimeSession) clear_diagnostics() {
	mut state := session.diagnostic_state
	state.errors = []RuntimeSessionDiagnostic{}
}

pub fn (mut session RuntimeSession) set_diagnostic_handler(handler RuntimeSessionDiagnosticHandler) {
	if session.closed {
		return
	}
	mut state := session.diagnostic_state
	state.handler = handler
}
