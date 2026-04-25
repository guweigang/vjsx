module vjsx

// Resolve a JS value into its settled result when it is a Promise.
// Non-Promise values are duplicated so callers always own the returned value.
pub fn (ctx &Context) resolve_value(val Value) !Value {
	if val.instanceof('Promise') {
		return ctx.js_await(val)
	}
	return val.dup_value()
}

// Resolve a JS value within the managed session.
pub fn (session RuntimeSession) resolve_value(val Value) !Value {
	return session.context.resolve_value(val)
}

// Call a JS function through the managed session without exposing raw Context
// call sites to embedders.
pub fn (session RuntimeSession) call(val Value, args ...AnyValue) !Value {
	return session.context.call(val, ...args)
}

// Call a global function by name through the managed session.
pub fn (session RuntimeSession) call_global(name string, args ...AnyValue) !Value {
	handler := session.context.js_global(name)
	defer {
		handler.free()
	}
	if handler.is_undefined() || !handler.is_function() {
		return error('global function not found: ${name}')
	}
	return session.call(handler, ...args)
}

// Call a JS function and resolve its final value when it returns a Promise.
pub fn (session RuntimeSession) call_resolved(val Value, args ...AnyValue) !Value {
	result := session.call(val, ...args)!
	defer {
		result.free()
	}
	return session.resolve_value(result)
}

// Call a global function by name and resolve its final value when it returns a
// Promise.
pub fn (session RuntimeSession) call_global_resolved(name string, args ...AnyValue) !Value {
	result := session.call_global(name, ...args)!
	defer {
		result.free()
	}
	return session.resolve_value(result)
}

// Load a module export and resolve its final value when it returns a Promise.
pub fn (session RuntimeSession) call_module_export_resolved(path string, export_name string, args ...AnyValue) !Value {
	result := session.call_module_export(path, export_name, ...args)!
	defer {
		result.free()
	}
	return session.resolve_value(result)
}

// Load a module method and resolve its final value when it returns a Promise.
pub fn (session RuntimeSession) call_module_method_resolved(path string, export_name string, method_name string, args ...AnyValue) !Value {
	result := session.call_module_method(path, export_name, method_name, ...args)!
	defer {
		result.free()
	}
	return session.resolve_value(result)
}

// Load a default export method and resolve its final value when it returns a
// Promise.
pub fn (session RuntimeSession) call_default_export_method_resolved(path string, method_name string, args ...AnyValue) !Value {
	result := session.call_default_export_method(path, method_name, ...args)!
	defer {
		result.free()
	}
	return session.resolve_value(result)
}
