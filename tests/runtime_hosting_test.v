import runtimejs
import time
import vjsx

fn runtime_hosting_eval_answer(ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('40 + 2')
}

fn runtime_hosting_eval_error(ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('throw new Error("turn boom")')
}

fn runtime_hosting_eval_forever(ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('while (true) {}')
}

fn runtime_hosting_slow_turn(ctx &vjsx.Context) !vjsx.Value {
	time.sleep(40 * time.millisecond)
	return ctx.eval('"slow"')
}

fn runtime_hosting_fast_turn(ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('"fast"')
}

fn runtime_hosting_run_slow(lane &runtimejs.SessionLane, done chan string) {
	value := lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'slow'
	}, runtime_hosting_slow_turn) or {
		done <- 'error:${err.msg()}'
		return
	}
	done <- value.to_string()
	value.free()
}

fn runtime_hosting_run_fast(lane &runtimejs.SessionLane, done chan string) {
	value := lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'queued-fast'
	}, runtime_hosting_fast_turn) or {
		done <- 'error:${err.msg()}'
		return
	}
	done <- value.to_string()
	value.free()
}

fn test_runtime_engine_limits_and_memory_snapshot() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_engine_limits(vjsx.RuntimeEngineLimits{
		memory_limit_bytes:      64 * 1024 * 1024
		max_stack_size_bytes:    2 * 1024 * 1024
		gc_threshold_bytes:      4 * 1024 * 1024
		default_turn_timeout_ms: 500
	})
	limits := session.engine_limits()
	assert limits.memory_limit_bytes == 64 * 1024 * 1024
	assert limits.max_stack_size_bytes == 2 * 1024 * 1024
	assert limits.default_turn_timeout_ms == 500
	memory := session.memory_usage()
	assert memory.malloc_size > 0
	assert memory.memory_used_size > 0
	assert memory.malloc_limit == 64 * 1024 * 1024
	snapshot := session.debug_snapshot()
	assert snapshot.memory.memory_used_size > 0
}

fn test_session_lane_admission_policy_is_pure_and_explicit() {
	config := runtimejs.SessionLaneConfig{
		max_queue:         2
		admission_wait_ms: 10
	}
	assert runtimejs.decide_session_lane_admission(runtimejs.SessionLaneLoad{}, config) == .admit
	assert runtimejs.decide_session_lane_admission(runtimejs.SessionLaneLoad{
		queued: 2
	}, config) == .refuse_full
	assert runtimejs.decide_session_lane_admission(runtimejs.SessionLaneLoad{
		draining: true
	}, config) == .refuse_draining
	assert !runtimejs.session_lane_admission_timed_out(9, 10)
	assert runtimejs.session_lane_admission_timed_out(10, 10)
}

fn test_runtime_turn_tracks_lifecycle_and_observation() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		session_id: 'hosting-test'
	})
	value := session.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind:          'answer'
		queue_wait_ms: 7
	}, runtime_hosting_eval_answer) or { panic(err) }
	assert value.to_int() == 42
	value.free()
	lifecycle := session.lifecycle_snapshot()
	assert lifecycle.phase == .ready
	assert lifecycle.in_flight_turns == 0
	assert lifecycle.completed_turns == 1
	observations := session.observations()
	assert observations.len == 1
	assert observations[0].session_id == 'hosting-test'
	assert observations[0].kind == 'answer'
	assert observations[0].outcome == .ok
	assert observations[0].queue_wait_ms == 7
	assert observations[0].memory_before_bytes > 0
	assert observations[0].memory_after_bytes > 0
}

fn test_runtime_turn_error_and_observations_are_bounded() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_limits(vjsx.RuntimeSessionLimits{
		max_observations: 2
	})
	session.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'error'
	}, runtime_hosting_eval_error) or { assert err.msg().contains('turn boom') }
	for index in 0 .. 2 {
		value := session.run_turn(vjsx.RuntimeSessionTurnOptions{
			kind: 'ok-${index}'
		}, runtime_hosting_eval_answer) or { panic(err) }
		value.free()
	}
	assert session.phase() == .ready
	assert session.lifecycle_snapshot().completed_turns == 3
	assert session.observation_count() == 2
	assert session.dropped_observation_count() == 1
	assert session.observations()[0].kind == 'ok-0'
}

fn test_runtime_turn_default_deadline_poisons_session() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_engine_limits(vjsx.RuntimeEngineLimits{
		default_turn_timeout_ms: 25
	})
	started := time.now()
	session.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'forever'
	}, runtime_hosting_eval_forever) or {
		assert err.msg().contains('deadline exceeded')
		assert session.phase() == .poisoned
		assert time.since(started) < 2 * time.second
		observations := session.observations()
		assert observations.len == 1
		assert observations[0].outcome == .interrupted
		return
	}
	assert false
}

fn test_session_lane_serializes_turns_and_drains() {
	mut lane := runtimejs.new_session_lane(vjsx.new_runtime_session(), runtimejs.SessionLaneConfig{
		max_queue:         2
		admission_wait_ms: 500
	})
	done := chan string{cap: 1}
	slow_thread := spawn runtime_hosting_run_slow(lane, done)
	time.sleep(10 * time.millisecond)
	fast := lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'fast'
	}, runtime_hosting_fast_turn) or { panic(err) }
	assert fast.to_string() == 'fast'
	fast.free()
	assert <-done == 'slow'
	slow_thread.wait()
	snapshot := lane.snapshot()
	assert snapshot.completed == 2
	assert snapshot.running == false
	assert snapshot.queued == 0
	observations := lane.observations()
	assert observations.len == 2
	assert observations.any(it.queue_wait_ms > 0)
	lane.begin_drain()
	lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'after-drain'
	}, runtime_hosting_fast_turn) or { assert err.msg().contains('draining') }
	assert lane.snapshot().rejected_draining == 1
	lane.close()
	assert lane.debug_snapshot().phase == .closed
}

fn test_session_lane_enforces_admission_timeout() {
	mut lane := runtimejs.new_session_lane(vjsx.new_runtime_session(), runtimejs.SessionLaneConfig{
		max_queue:         2
		admission_wait_ms: 5
	})
	done := chan string{cap: 1}
	slow_thread := spawn runtime_hosting_run_slow(lane, done)
	for !lane.snapshot().running {
		time.sleep(time.millisecond)
	}
	lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'timeout'
	}, runtime_hosting_fast_turn) or { assert err.msg().contains('timed out') }
	assert <-done == 'slow'
	slow_thread.wait()
	assert lane.snapshot().rejected_timeout == 1
	lane.close()
}

fn test_session_lane_enforces_queue_limit() {
	mut lane := runtimejs.new_session_lane(vjsx.new_runtime_session(), runtimejs.SessionLaneConfig{
		max_queue:         1
		admission_wait_ms: 500
	})
	slow_done := chan string{cap: 1}
	fast_done := chan string{cap: 1}
	slow_thread := spawn runtime_hosting_run_slow(lane, slow_done)
	for !lane.snapshot().running {
		time.sleep(time.millisecond)
	}
	fast_thread := spawn runtime_hosting_run_fast(lane, fast_done)
	for lane.snapshot().queued != 1 {
		time.sleep(time.millisecond)
	}
	lane.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'queue-full'
	}, runtime_hosting_fast_turn) or { assert err.msg().contains('queue is full') }
	assert <-slow_done == 'slow'
	assert <-fast_done == 'fast'
	slow_thread.wait()
	fast_thread.wait()
	assert lane.snapshot().rejected_full == 1
	lane.close()
}
