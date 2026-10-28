module vjsx

fn bound_script_plugin_missing_host_api(ctx &Context) Value {
	return ctx.js_undefined()
}

// BoundScriptPlugin binds a reusable host API object/value to a plugin handle,
// so embedders can call lifecycle hooks without manually passing the host
// context on every call.
pub struct BoundScriptPlugin {
	host_api HostValueBuilder = bound_script_plugin_missing_host_api
mut:
	plugin ScriptPlugin
}

// Build a bound plugin handle from an existing plugin handle plus a reusable
// host context object/value.
pub fn new_bound_script_plugin(host_api HostValueBuilder, plugin_handle ScriptPlugin) BoundScriptPlugin {
	return BoundScriptPlugin{
		host_api: host_api
		plugin:   plugin_handle
	}
}

// Report the bound plugin name.
pub fn (binding BoundScriptPlugin) name() string {
	return binding.plugin.name()
}

// Report the bound plugin path.
pub fn (binding BoundScriptPlugin) path() string {
	return binding.plugin.path()
}

// Report the declared plugin capabilities.
pub fn (binding BoundScriptPlugin) capabilities() []string {
	return binding.plugin.capabilities()
}

// Check whether the plugin declares a named capability.
pub fn (binding BoundScriptPlugin) has_capability(name string) bool {
	return binding.plugin.has_capability(name)
}

// Report whether the underlying plugin handle has been closed.
pub fn (binding BoundScriptPlugin) is_closed() bool {
	return binding.plugin.is_closed()
}

// Access the underlying plugin handle.
pub fn (binding BoundScriptPlugin) plugin_handle() ScriptPlugin {
	return binding.plugin
}

// Access the underlying module handle.
pub fn (binding BoundScriptPlugin) module_handle() ScriptModule {
	return binding.plugin.module_handle()
}

// Run the bound plugin activation hook with the configured host context.
pub fn (binding BoundScriptPlugin) activate(args ...AnyValue) !Value {
	return binding.plugin.activate_with_host(binding.host_api, ...args)
}

// Run the bound plugin handler hook with the configured host context.
pub fn (binding BoundScriptPlugin) handle(args ...AnyValue) !Value {
	return binding.plugin.handle_with_host(binding.host_api, ...args)
}

// Run the bound plugin dispose hook with the configured host context.
pub fn (binding BoundScriptPlugin) dispose(args ...AnyValue) !Value {
	return binding.plugin.dispose_with_host(binding.host_api, ...args)
}

// Free the underlying plugin handle. Safe to call more than once.
pub fn (mut binding BoundScriptPlugin) close() {
	binding.plugin.close()
}
