module vjsx

fn bound_script_module_missing_host_api(ctx &Context) Value {
	return ctx.js_undefined()
}

// BoundScriptModule binds a reusable host API object/value to a module handle,
// so embedders can call exports and export methods without manually passing the
// host context on every call.
pub struct BoundScriptModule {
	host_api    HostValueBuilder = bound_script_module_missing_host_api
	script_path string
mut:
	module ScriptModule
}

// Build a bound module handle from an existing module handle plus a reusable
// host context object/value.
pub fn new_bound_script_module(path string, host_api HostValueBuilder, module_handle ScriptModule) BoundScriptModule {
	return BoundScriptModule{
		host_api:    host_api
		script_path: path
		module:      module_handle
	}
}

// Report the resolved module path.
pub fn (binding BoundScriptModule) path() string {
	return binding.script_path
}

// Report whether the underlying module handle has been closed.
pub fn (binding BoundScriptModule) is_closed() bool {
	return binding.module.is_closed()
}

// Access the underlying module handle.
pub fn (binding BoundScriptModule) module_handle() ScriptModule {
	return binding.module
}

// Report whether a named export exists.
pub fn (binding BoundScriptModule) has_export(name string) bool {
	return binding.module.has_export(name)
}

// Return a duplicate of the module namespace object.
pub fn (binding BoundScriptModule) namespace() !Value {
	return binding.module.namespace()
}

// Return a duplicate of a named export.
pub fn (binding BoundScriptModule) get_export(name string) !Value {
	return binding.module.get_export(name)
}

// Return a duplicate of the default export.
pub fn (binding BoundScriptModule) default_export() !Value {
	return binding.module.default_export()
}

// Call a named function export with the configured host context.
pub fn (binding BoundScriptModule) call_export(name string, args ...AnyValue) !Value {
	return binding.module.call_export_with_host(name, binding.host_api, ...args)
}

// Call a named export when it exists, otherwise return `undefined`.
pub fn (binding BoundScriptModule) call_export_if_present(name string, args ...AnyValue) !Value {
	if !binding.has_export(name) {
		return binding.module.ctx.js_undefined()
	}
	return binding.call_export(name, ...args)
}

// Call a method on an exported object with the configured host context.
pub fn (binding BoundScriptModule) call_export_method(export_name string, method_name string, args ...AnyValue) !Value {
	return binding.module.call_export_method_with_host(export_name, method_name, binding.host_api,
		...args)
}

// Call a method on the default export object with the configured host context.
pub fn (binding BoundScriptModule) call_default_method(method_name string, args ...AnyValue) !Value {
	return binding.module.call_default_method_with_host(method_name, binding.host_api,
		...args)
}

// Free the underlying module handle. Safe to call more than once.
pub fn (mut binding BoundScriptModule) close() {
	binding.module.close()
}
