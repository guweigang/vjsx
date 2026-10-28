import vjsx

fn settle_cancel_memory_operations(mut session vjsx.RuntimeSession, count int) ! {
	for _ in 0 .. count {
		operation := session.start_host_async_operation(kind: 'memory-regression')!
		assert operation.completion.resolve_text('ok')
		assert session.drain_host_async_events()! == 1
		session.drain_ready_tasks()!
		operation.promise.free()
	}
}

fn test_host_async_cancellation_does_not_retain_one_native_closure_per_operation() ! {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	settle_cancel_memory_operations(mut session, 100)!
	gc_collect()
	before := gc_memory_use()
	settle_cancel_memory_operations(mut session, 5000)!
	gc_collect()
	after := gc_memory_use()
	assert session.pending_host_async_operation_count() == 0
	if gc_is_enabled() {
		assert after <= before + 2 * 1024 * 1024, 'native heap grew from ${before} to ${after}'
	}
}

fn test_retained_cancellation_callback_is_safe_after_completion_and_does_not_cancel_next_operation() ! {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	first := session.start_host_async_operation()!
	cancel := first.promise.get('__vjsxCancel')
	defer { cancel.free() }
	assert first.completion.resolve_text('done')
	assert session.drain_host_async_events()! == 1
	session.drain_ready_tasks()!
	first.promise.free()
	second := session.start_host_async_operation()!
	late := session.context().call(cancel, 'too late')!
	assert !late.to_bool()
	late.free()
	assert !second.cancel.is_cancelled()
	assert second.completion.resolve_text('second')
	assert session.drain_host_async_events()! == 1
	session.drain_ready_tasks()!
	second.promise.free()
}
