module vjsx

// AsyncIteratorResult is one settled result from an async iterator `next()`
// call. Callers own `value` and must free it.
pub struct AsyncIteratorResult {
pub:
	done  bool
	value Value
}

pub struct AsyncIterator {
mut:
	iterator Value
	closed   bool
	freed    bool
}

// Report whether a JS value exposes `Symbol.asyncIterator`.
pub fn (ctx &Context) is_async_iterable(val Value) bool {
	helper := ctx.eval('(value) => value != null && typeof value[Symbol.asyncIterator] === "function"') or {
		return false
	}
	defer {
		helper.free()
	}
	result := ctx.call(helper, val) or { return false }
	defer {
		result.free()
	}
	return result.to_bool()
}

// Create an AsyncIterator wrapper from a JS async iterable.
pub fn (ctx &Context) async_iterator(val Value) !AsyncIterator {
	helper := ctx.eval('
		(value) => {
			if (value == null || typeof value[Symbol.asyncIterator] !== "function") {
				throw new TypeError("value is not an async iterable");
			}
			const iterator = value[Symbol.asyncIterator]();
			if (iterator == null || typeof iterator.next !== "function") {
				throw new TypeError("async iterator does not expose next()");
			}
			return iterator;
		}
	')!
	defer {
		helper.free()
	}
	iterator := ctx.call(helper, val)!
	return AsyncIterator{
		iterator: iterator
	}
}

// Pull and await one async iterator frame.
pub fn (mut iter AsyncIterator) next() !AsyncIteratorResult {
	if iter.closed || iter.freed {
		return error('async iterator is closed')
	}
	next_fn := iter.iterator.get('next')
	defer {
		next_fn.free()
	}
	if !next_fn.is_function() {
		return error('async iterator next property is not callable')
	}
	promise := iter.iterator.ctx.call_this(iter.iterator, next_fn)!
	defer {
		promise.free()
	}
	result := iter.iterator.ctx.resolve_value(promise)!
	defer {
		result.free()
	}
	done_value := result.get('done')
	done := done_value.to_bool()
	done_value.free()
	if done {
		iter.closed = true
		return AsyncIteratorResult{
			done:  true
			value: iter.iterator.ctx.js_undefined()
		}
	}
	value := result.get('value')
	return AsyncIteratorResult{
		done:  false
		value: value
	}
}

// Ask JS to cancel the iterator by calling `return()` when available.
pub fn (mut iter AsyncIterator) cancel(reason AnyValue) !Value {
	if iter.closed || iter.freed {
		return iter.iterator.ctx.js_undefined()
	}
	return_fn := iter.iterator.get('return')
	defer {
		return_fn.free()
	}
	iter.closed = true
	if return_fn.is_undefined() {
		return iter.iterator.ctx.js_undefined()
	}
	if !return_fn.is_function() {
		return error('async iterator return property is not callable')
	}
	promise := iter.iterator.ctx.call_this(iter.iterator, return_fn, reason)!
	defer {
		promise.free()
	}
	return iter.iterator.ctx.resolve_value(promise)
}

// Free the wrapped JS iterator. This does not call `return()`; use cancel()
// first when the JS side should observe cancellation.
pub fn (mut iter AsyncIterator) close() {
	if iter.freed {
		return
	}
	iter.iterator.free()
	iter.closed = true
	iter.freed = true
}
