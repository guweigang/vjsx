module vjsx

import sync

pub enum RuntimeSessionObservationOutcome {
	ok
	error
	interrupted
}

// RuntimeSessionObservation is one bounded, structured record of a JS turn.
// It is retained for polling; recording never invokes user code on the hot path.
pub struct RuntimeSessionObservation {
pub:
	session_id          string
	kind                string
	outcome             RuntimeSessionObservationOutcome
	message             string
	at_ms               i64
	duration_ms         i64
	queue_wait_ms       i64
	memory_before_bytes i64
	memory_after_bytes  i64
}

struct RuntimeSessionObservationState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	events []RuntimeSessionObservation
}

fn new_runtime_session_observation_state() &RuntimeSessionObservationState {
	return &RuntimeSessionObservationState{
		events: []RuntimeSessionObservation{}
	}
}

fn (session RuntimeSession) record_observation(event RuntimeSessionObservation) {
	if session.closed || session.event_loop_state.closed {
		return
	}
	mut state := session.observation_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	max_observations := session.limit_state.config.max_observations
	if max_observations > 0 && state.events.len >= max_observations {
		state.events.delete(0)
		mut limits := session.limit_state
		limits.dropped_observations++
	}
	state.events << event
}

pub fn (session RuntimeSession) observations() []RuntimeSessionObservation {
	mut state := session.observation_state
	state.guard.lock()
	events := state.events.clone()
	state.guard.unlock()
	return events
}

pub fn (session RuntimeSession) observation_count() int {
	mut state := session.observation_state
	state.guard.lock()
	count := state.events.len
	state.guard.unlock()
	return count
}

pub fn (session RuntimeSession) clear_observations() {
	mut state := session.observation_state
	state.guard.lock()
	state.events = []RuntimeSessionObservation{}
	state.guard.unlock()
}
