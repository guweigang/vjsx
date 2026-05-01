module vjsx

pub type RuntimeSessionStreamFrameFn = fn (Value) !bool

// Report whether a JS value can be streamed by the host as an async iterable.
pub fn (session RuntimeSession) is_streamable_value(val Value) bool {
	return session.context.is_async_iterable(val)
}

// Pull an async iterable one frame at a time. The callback is invoked only
// after the previous JS `next()` has settled, so hosts can apply backpressure
// by returning from the callback only after the downstream write is ready.
// Return false from the callback to cancel the JS iterator. The returned bool
// is true when the iterator completed naturally and false when it was cancelled.
pub fn (session RuntimeSession) stream_value(val Value, on_frame RuntimeSessionStreamFrameFn) !bool {
	mut iter := session.context.async_iterator(val) or {
		session.record_runtime_error('stream_value', err.msg())
		return err
	}
	defer {
		iter.close()
	}
	for {
		next := iter.next() or {
			session.record_runtime_error('stream_value', err.msg())
			return err
		}
		if next.done {
			next.value.free()
			return true
		}
		should_continue := on_frame(next.value) or {
			message := err.msg()
			next.value.free()
			cancel_result := iter.cancel(message) or {
				session.record_runtime_error('stream_value_cancel', err.msg())
				return error(message)
			}
			cancel_result.free()
			return error(message)
		}
		next.value.free()
		if !should_continue {
			cancel_result := iter.cancel('stream cancelled') or {
				session.record_runtime_error('stream_value_cancel', err.msg())
				return err
			}
			cancel_result.free()
			return false
		}
	}
	return true
}
