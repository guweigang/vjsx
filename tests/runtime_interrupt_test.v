import time
import vjsx

fn runtime_interrupt_test_cancel_after(session vjsx.RuntimeSession, delay time.Duration) {
	time.sleep(delay)
	session.cancel()
}

fn test_runtime_session_deadline_interrupts_non_yielding_javascript() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.set_deadline(time.now().add(30 * time.millisecond))
	started := time.now()
	session.context().eval('while (true) {}') or {
		assert err.msg().contains('deadline exceeded')
		assert session.interrupt_reason() == .deadline
		assert session.is_interrupted()
		assert time.since(started) < 2 * time.second
		// Interruptions poison the runtime; clearing the old deadline must not
		// make the session executable again.
		session.clear_deadline()
		session.context().eval('1 + 1') or {
			assert err.msg().contains('deadline exceeded')
			return
		}
		assert false
		return
	}
	assert false
}

fn test_runtime_session_cancel_is_observed_during_javascript_execution() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	cancel_thread := spawn runtime_interrupt_test_cancel_after(session, 30 * time.millisecond)
	session.context().eval('for (;;) {}') or {
		cancel_thread.wait()
		assert err.msg().contains('execution cancelled')
		assert session.interrupt_reason() == .cancelled
		assert session.is_interrupted()
		return
	}
	cancel_thread.wait()
	assert false
}

fn test_runtime_session_clear_deadline_keeps_session_usable_before_interrupt() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.set_deadline(time.now().add(20 * time.millisecond))
	session.clear_deadline()
	time.sleep(30 * time.millisecond)
	value := session.context().eval('40 + 2') or { panic(err) }
	defer {
		value.free()
	}
	assert value.to_int() == 42
	assert !session.is_interrupted()
}
