module vjsx

import time
import sync

// RuntimeSessionPhase is the host-visible lifecycle of one managed runtime.
pub enum RuntimeSessionPhase {
	ready
	running
	draining
	poisoned
	closed
}

struct RuntimeSessionLifecycleState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	phase           RuntimeSessionPhase = .ready
	in_flight_turns int
	completed_turns u64
	rejected_turns  u64
	drain_requested bool
}

pub struct RuntimeSessionLifecycleSnapshot {
pub:
	phase           RuntimeSessionPhase
	in_flight_turns int
	completed_turns u64
	rejected_turns  u64
}

pub type RuntimeSessionTurnFn = fn (&Context) !Value

@[params]
pub struct RuntimeSessionTurnOptions {
pub:
	kind          string = 'turn'
	timeout_ms    u64
	queue_wait_ms i64
}

fn new_runtime_session_lifecycle_state() &RuntimeSessionLifecycleState {
	return &RuntimeSessionLifecycleState{}
}

pub fn (session RuntimeSession) lifecycle_snapshot() RuntimeSessionLifecycleSnapshot {
	mut state := session.lifecycle_state
	state.guard.lock()
	mut phase := state.phase
	if phase != .closed && session.is_interrupted() {
		phase = .poisoned
	}
	snapshot := RuntimeSessionLifecycleSnapshot{
		phase:           phase
		in_flight_turns: state.in_flight_turns
		completed_turns: state.completed_turns
		rejected_turns:  state.rejected_turns
	}
	state.guard.unlock()
	return snapshot
}

pub fn (session RuntimeSession) phase() RuntimeSessionPhase {
	return session.lifecycle_snapshot().phase
}

pub fn (session RuntimeSession) is_running() bool {
	return session.lifecycle_snapshot().in_flight_turns > 0
}

// Begin draining this session. New turns are rejected; the current turn, if
// any, may finish before the owner calls close().
pub fn (session RuntimeSession) begin_drain() bool {
	mut state := session.lifecycle_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	if state.phase in [.closed, .poisoned] {
		return false
	}
	state.drain_requested = true
	state.phase = .draining
	return true
}

fn (session RuntimeSession) begin_turn() ! {
	mut state := session.lifecycle_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	if session.is_interrupted() {
		state.phase = .poisoned
	}
	match state.phase {
		.ready {
			state.phase = .running
			state.in_flight_turns++
		}
		.running {
			state.rejected_turns++
			return error('runtime session already has a turn in flight')
		}
		.draining {
			state.rejected_turns++
			return error('runtime session is draining')
		}
		.poisoned {
			state.rejected_turns++
			return error('runtime session is poisoned and must be closed')
		}
		.closed {
			state.rejected_turns++
			return error('runtime session is closed')
		}
	}
}

fn (session RuntimeSession) finish_turn() {
	mut state := session.lifecycle_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	if state.in_flight_turns > 0 {
		state.in_flight_turns--
	}
	state.completed_turns++
	state.phase = if session.is_interrupted() {
		.poisoned
	} else if state.drain_requested {
		.draining
	} else {
		.ready
	}
}

fn (session RuntimeSession) mark_closing() {
	mut state := session.lifecycle_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	if state.phase != .closed {
		state.drain_requested = true
		state.phase = .draining
	}
}

fn (session RuntimeSession) mark_closed() {
	mut state := session.lifecycle_state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	state.in_flight_turns = 0
	state.drain_requested = true
	state.phase = .closed
}

// Run one synchronous entry into QuickJS with lifecycle, deadline, memory and
// observation bookkeeping. Hosts that serialize work should make this their
// only entry point into a session.
pub fn (session RuntimeSession) run_turn(options RuntimeSessionTurnOptions, action RuntimeSessionTurnFn) !Value {
	session.begin_turn()!
	started_at_ms := session.now_ms()
	started_tick := time.ticks()
	memory_before := session.memory_usage()
	timeout_ms := if options.timeout_ms > 0 {
		options.timeout_ms
	} else {
		session.engine_limits().default_turn_timeout_ms
	}
	if timeout_ms > 0 {
		session.runtime.set_deadline_after_ms(timeout_ms)
	}
	result := action(session.context) or {
		if timeout_ms > 0 && !session.is_interrupted() {
			session.runtime.clear_deadline()
		}
		duration_ms := time.ticks() - started_tick
		memory_after := session.memory_usage()
		session.finish_turn()
		session.record_observation(RuntimeSessionObservation{
			session_id:          session.event_loop_state.config.session_id
			kind:                options.kind
			outcome:             if session.is_interrupted() { .interrupted } else { .error }
			message:             err.msg()
			at_ms:               started_at_ms
			duration_ms:         duration_ms
			queue_wait_ms:       options.queue_wait_ms
			memory_before_bytes: memory_before.memory_used_size
			memory_after_bytes:  memory_after.memory_used_size
		})
		session.record_runtime_error('turn_${options.kind}', err.msg())
		return err
	}
	if timeout_ms > 0 {
		session.runtime.clear_deadline()
	}
	duration_ms := time.ticks() - started_tick
	memory_after := session.memory_usage()
	session.finish_turn()
	session.record_observation(RuntimeSessionObservation{
		session_id:          session.event_loop_state.config.session_id
		kind:                options.kind
		outcome:             .ok
		at_ms:               started_at_ms
		duration_ms:         duration_ms
		queue_wait_ms:       options.queue_wait_ms
		memory_before_bytes: memory_before.memory_used_size
		memory_after_bytes:  memory_after.memory_used_size
	})
	return result
}
