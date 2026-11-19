module vjsx

import time

fn test_interrupt_deadline_targets_only_selected_context() {
	rt := new_runtime()
	ctx_target := rt.new_context()
	ctx_other := rt.new_context()
	defer {
		ctx_other.free()
		ctx_target.free()
		rt.free()
	}

	rt.set_deadline_after_ms(ctx_target.ref, 1)
	time.sleep(5 * time.millisecond)

	other_before := ctx_other.eval('40 + 2') or { panic(err) }
	assert other_before.to_int() == 42
	other_before.free()
	assert rt.interrupt_reason(ctx_other.ref) == .none

	ctx_target.eval('while (true) {}') or {
		assert err.msg().contains('deadline exceeded')
		assert rt.interrupt_reason(ctx_target.ref) == .deadline
		other_after := ctx_other.eval('1 + 1') or { panic(err) }
		assert other_after.to_int() == 2
		other_after.free()
		queued := ctx_other.eval('Promise.resolve(41).then(value => globalThis.__interrupt_other = value + 1)') or {
			panic(err)
		}
		queued.free()
		ctx_other.drain_ready_tasks() or { panic(err) }
		job_result := ctx_other.js_global('__interrupt_other')
		assert job_result.to_int() == 42
		job_result.free()
		return
	}
	assert false
}
