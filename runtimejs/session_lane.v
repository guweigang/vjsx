module runtimejs

import sync
import time
import vjsx

pub const default_session_lane_max_queue = 64
pub const default_session_lane_admission_wait_ms = u64(1000)

@[params]
pub struct SessionLaneConfig {
pub:
	// Zero means no waiting queue limit.
	max_queue         int = default_session_lane_max_queue
	admission_wait_ms u64 = default_session_lane_admission_wait_ms
}

struct SessionLaneState {
	guard     &sync.Mutex = sync.new_mutex()
	turn_gate &sync.Mutex = sync.new_mutex()
mut:
	queued            int
	running           bool
	draining          bool
	completed         u64
	rejected_full     u64
	rejected_timeout  u64
	rejected_draining u64
}

pub struct SessionLaneSnapshot {
pub:
	queued            int
	running           bool
	draining          bool
	completed         u64
	rejected_full     u64
	rejected_timeout  u64
	rejected_draining u64
	session           vjsx.RuntimeSessionLifecycleSnapshot
}

// SessionLane serializes all entries into one RuntimeSession and bounds the
// number of callers waiting to enter it. Ownership of session transfers to the
// lane; callers must not use or close their old copy afterwards.
pub struct SessionLane {
	config SessionLaneConfig
	state  &SessionLaneState = &SessionLaneState{}
mut:
	session vjsx.RuntimeSession
}

pub fn new_session_lane(session vjsx.RuntimeSession, config SessionLaneConfig) &SessionLane {
	return &SessionLane{
		config:  config
		session: session
	}
}

pub fn new_script_session_lane(ctx_config vjsx.ContextConfig, runtime_config vjsx.ScriptRuntimeConfig, config SessionLaneConfig) &SessionLane {
	return new_session_lane(new_script_runtime_session(ctx_config, runtime_config), config)
}

pub fn new_node_session_lane(ctx_config vjsx.ContextConfig, runtime_config vjsx.NodeRuntimeConfig, config SessionLaneConfig) &SessionLane {
	return new_session_lane(new_node_runtime_session(ctx_config, runtime_config), config)
}

fn (lane &SessionLane) reserve_waiter() ! {
	mut state := lane.state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	decision := decide_session_lane_admission(SessionLaneLoad{
		queued:   state.queued
		running:  state.running
		draining: state.draining
	}, lane.config)
	match decision {
		.refuse_draining {
			state.rejected_draining++
			return error('session lane is draining')
		}
		.refuse_full {
			state.rejected_full++
			return error('session lane queue is full')
		}
		.admit {}
	}
	state.queued++
}

fn (lane &SessionLane) cancel_waiter(timed_out bool) {
	mut state := lane.state
	state.guard.lock()
	if state.queued > 0 {
		state.queued--
	}
	if timed_out {
		state.rejected_timeout++
	}
	state.guard.unlock()
}

fn (lane &SessionLane) acquire_turn() !i64 {
	lane.reserve_waiter()!
	started := time.ticks()
	mut state := lane.state
	for {
		if state.turn_gate.try_lock() {
			state.guard.lock()
			if state.queued > 0 {
				state.queued--
			}
			if state.draining {
				state.rejected_draining++
				state.guard.unlock()
				state.turn_gate.unlock()
				return error('session lane is draining')
			}
			state.running = true
			state.guard.unlock()
			return time.ticks() - started
		}
		if session_lane_admission_timed_out(u64(time.ticks() - started),
			lane.config.admission_wait_ms)
		{
			lane.cancel_waiter(true)
			return error('session lane admission timed out')
		}
		time.sleep(time.millisecond)
	}
	return error('session lane admission failed')
}

fn (lane &SessionLane) release_turn(completed bool) {
	mut state := lane.state
	state.guard.lock()
	state.running = false
	if completed {
		state.completed++
	}
	state.guard.unlock()
	state.turn_gate.unlock()
}

pub fn (lane &SessionLane) run_turn(options vjsx.RuntimeSessionTurnOptions, action vjsx.RuntimeSessionTurnFn) !vjsx.Value {
	queue_wait_ms := lane.acquire_turn()!
	completed_before := lane.session.lifecycle_snapshot().completed_turns
	result := lane.session.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind:          options.kind
		timeout_ms:    options.timeout_ms
		queue_wait_ms: queue_wait_ms
	}, action) or {
		completed := lane.session.lifecycle_snapshot().completed_turns > completed_before
		lane.release_turn(completed)
		return err
	}
	lane.release_turn(true)
	return result
}

// Stop admitting work. Waiting callers are rejected when they reach the gate.
pub fn (lane &SessionLane) begin_drain() {
	mut state := lane.state
	state.guard.lock()
	state.draining = true
	state.guard.unlock()
	lane.session.begin_drain()
}

pub fn (lane &SessionLane) snapshot() SessionLaneSnapshot {
	mut state := lane.state
	state.guard.lock()
	snapshot := SessionLaneSnapshot{
		queued:            state.queued
		running:           state.running
		draining:          state.draining
		completed:         state.completed
		rejected_full:     state.rejected_full
		rejected_timeout:  state.rejected_timeout
		rejected_draining: state.rejected_draining
		session:           lane.session.lifecycle_snapshot()
	}
	state.guard.unlock()
	return snapshot
}

pub fn (lane &SessionLane) debug_snapshot() vjsx.RuntimeSessionDebugSnapshot {
	mut state := lane.state
	state.turn_gate.lock()
	snapshot := lane.session.debug_snapshot()
	state.turn_gate.unlock()
	return snapshot
}

pub fn (lane &SessionLane) observations() []vjsx.RuntimeSessionObservation {
	return lane.session.observations()
}

// Drain and close the owned session. This waits for the current turn gate.
pub fn (mut lane SessionLane) close() {
	lane.begin_drain()
	mut state := lane.state
	state.turn_gate.lock()
	lane.session.close()
	state.turn_gate.unlock()
}
