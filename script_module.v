module vjsx

// ScriptModule wraps a loaded JS/TS module namespace so embedders can inspect
// exports and call exported functions or object methods without juggling raw
// `Value` ownership at every call site.
struct ScriptModuleState {
mut:
	closed bool
}

pub struct ScriptModule {
	ctx     &Context
	exports Value
	state   &ScriptModuleState
}

fn (mod ScriptModule) ensure_open() ! {
	if mod.state.closed {
		return error('script module is closed')
	}
}

fn (mod ScriptModule) require_export(name string) !Value {
	mod.ensure_open()!
	value := mod.exports.get(name)
	if value.is_undefined() {
		value.free()
		return error('module export not found: ${name}')
	}
	return value
}

// Report whether a named export exists.
pub fn (mod ScriptModule) has_export(name string) bool {
	mod.ensure_open() or { return false }
	value := mod.exports.get(name)
	defer {
		value.free()
	}
	return !value.is_undefined()
}

// Report whether the script module has been closed.
pub fn (mod ScriptModule) is_closed() bool {
	return mod.state.closed
}

// Return a duplicate of the module namespace object.
pub fn (mod ScriptModule) namespace() !Value {
	mod.ensure_open()!
	return mod.exports.dup_value()
}

// Return a duplicate of a named export.
pub fn (mod ScriptModule) get_export(name string) !Value {
	value := mod.require_export(name)!
	defer {
		value.free()
	}
	return value.dup_value()
}

// Return a duplicate of the default export.
pub fn (mod ScriptModule) default_export() !Value {
	return mod.get_export('default')
}

// Call a named function export.
pub fn (mod ScriptModule) call_export(name string, args ...AnyValue) !Value {
	export_value := mod.require_export(name)!
	defer {
		export_value.free()
	}
	if !export_value.is_function() {
		return error('module export is not callable: ${name}')
	}
	return mod.ctx.call_this(mod.exports, export_value, ...args)
}

// Call a named function export with an explicit host context object/value as
// the first argument.
pub fn (mod ScriptModule) call_export_with_host(name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	host_value := host_api(mod.ctx)
	defer {
		host_value.free()
	}
	mut call_args := []AnyValue{cap: args.len + 1}
	call_args << host_value
	call_args << args
	return mod.call_export(name, ...call_args)
}

// Call a method on an exported object.
pub fn (mod ScriptModule) call_export_method(export_name string, method_name string, args ...AnyValue) !Value {
	export_value := mod.require_export(export_name)!
	defer {
		export_value.free()
	}
	if !export_value.is_object() {
		return error('module export is not an object: ${export_name}')
	}
	method := export_value.get(method_name)
	defer {
		method.free()
	}
	if !method.is_function() {
		return error('module export method is not callable: ${export_name}.${method_name}')
	}
	return mod.ctx.call_this(export_value, method, ...args)
}

// Call a method on an exported object with an explicit host context object/value
// as the first argument.
pub fn (mod ScriptModule) call_export_method_with_host(export_name string, method_name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	host_value := host_api(mod.ctx)
	defer {
		host_value.free()
	}
	mut call_args := []AnyValue{cap: args.len + 1}
	call_args << host_value
	call_args << args
	return mod.call_export_method(export_name, method_name, ...call_args)
}

// Call a method on the default export object.
pub fn (mod ScriptModule) call_default_method(method_name string, args ...AnyValue) !Value {
	return mod.call_export_method('default', method_name, ...args)
}

// Call a method on the default export object with an explicit host context
// object/value as the first argument.
pub fn (mod ScriptModule) call_default_method_with_host(method_name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	return mod.call_export_method_with_host('default', method_name, host_api, ...args)
}

// Call a named export when it exists, otherwise return `undefined`.
pub fn (mod ScriptModule) call_export_if_present(name string, args ...AnyValue) !Value {
	if !mod.has_export(name) {
		return mod.ctx.js_undefined()
	}
	return mod.call_export(name, ...args)
}

// Call a method on the default export object when it exists, otherwise return
// `undefined`.
pub fn (mod ScriptModule) call_default_method_if_present(method_name string, args ...AnyValue) !Value {
	if !mod.has_export('default') {
		return mod.ctx.js_undefined()
	}
	default_export := mod.require_export('default')!
	defer {
		default_export.free()
	}
	if !default_export.is_object() || !default_export.has(method_name) {
		return mod.ctx.js_undefined()
	}
	return mod.call_default_method(method_name, ...args)
}

// Free the wrapped module namespace. Safe to call more than once.
pub fn (mut mod ScriptModule) close() {
	if mod.state.closed {
		return
	}
	mod.exports.free()
	mut state := mod.state
	state.closed = true
}
