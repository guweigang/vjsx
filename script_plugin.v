module vjsx

@[params]
pub struct ScriptPluginHooks {
pub:
	name                  string
	activate_export       string = 'activate'
	handle_export         string = 'handle'
	dispose_export        string = 'dispose'
	capabilities          []string
	auto_dispose_on_close bool = true
}

// ScriptPlugin wraps a loaded module plus a simple lifecycle convention so
// embedders can treat JS/TS code like a hosted plugin.
pub struct ScriptPlugin {
	hooks       ScriptPluginHooks
	script_path string
mut:
	module ScriptModule
}

// Build a plugin handle from an existing loaded module.
pub fn new_script_plugin(path string, module_handle ScriptModule, hooks ScriptPluginHooks) ScriptPlugin {
	return ScriptPlugin{
		hooks:       hooks
		script_path: path
		module:      module_handle
	}
}

// Report the plugin name when explicitly configured, otherwise fall back to its
// loaded path.
pub fn (plugin ScriptPlugin) name() string {
	if plugin.hooks.name != '' {
		return plugin.hooks.name
	}
	return plugin.script_path
}

// Report the resolved plugin path.
pub fn (plugin ScriptPlugin) path() string {
	return plugin.script_path
}

// Report the plugin capability tags declared by the host.
pub fn (plugin ScriptPlugin) capabilities() []string {
	return plugin.hooks.capabilities.clone()
}

// Check whether the plugin handle has a declared capability tag.
pub fn (plugin ScriptPlugin) has_capability(name string) bool {
	return name in plugin.hooks.capabilities
}

// Report whether the plugin handle has already been closed.
pub fn (plugin ScriptPlugin) is_closed() bool {
	return plugin.module.is_closed()
}

// Access the underlying module handle.
pub fn (plugin ScriptPlugin) module_handle() ScriptModule {
	return plugin.module
}

// Run the plugin activation hook when present.
pub fn (plugin ScriptPlugin) activate(args ...AnyValue) !Value {
	return plugin.module.call_export_if_present(plugin.hooks.activate_export, ...args)
}

// Run the plugin activation hook with an explicit host context object/value as
// the first argument.
pub fn (plugin ScriptPlugin) activate_with_host(host_api HostValueBuilder, args ...AnyValue) !Value {
	host_value := host_api(plugin.module.ctx)
	defer {
		host_value.free()
	}
	mut call_args := []AnyValue{cap: args.len + 1}
	call_args << host_value
	call_args << args
	return plugin.module.call_export_if_present(plugin.hooks.activate_export, ...call_args)
}

// Run the plugin handler hook when present.
pub fn (plugin ScriptPlugin) handle(args ...AnyValue) !Value {
	return plugin.module.call_export_if_present(plugin.hooks.handle_export, ...args)
}

// Run the plugin handler hook with an explicit host context object/value as the
// first argument.
pub fn (plugin ScriptPlugin) handle_with_host(host_api HostValueBuilder, args ...AnyValue) !Value {
	host_value := host_api(plugin.module.ctx)
	defer {
		host_value.free()
	}
	mut call_args := []AnyValue{cap: args.len + 1}
	call_args << host_value
	call_args << args
	return plugin.module.call_export_if_present(plugin.hooks.handle_export, ...call_args)
}

// Run the plugin dispose hook when present.
pub fn (plugin ScriptPlugin) dispose(args ...AnyValue) !Value {
	return plugin.module.call_export_if_present(plugin.hooks.dispose_export, ...args)
}

// Run the plugin dispose hook with an explicit host context object/value as the
// first argument.
pub fn (plugin ScriptPlugin) dispose_with_host(host_api HostValueBuilder, args ...AnyValue) !Value {
	host_value := host_api(plugin.module.ctx)
	defer {
		host_value.free()
	}
	mut call_args := []AnyValue{cap: args.len + 1}
	call_args << host_value
	call_args << args
	return plugin.module.call_export_if_present(plugin.hooks.dispose_export, ...call_args)
}

// Free the underlying module handle. Safe to call more than once.
pub fn (mut plugin ScriptPlugin) close() {
	plugin.module.close()
}
