module runtimejs

import vjsx

fn extension_session_missing_host_api(ctx &vjsx.Context) vjsx.Value {
	return ctx.js_undefined()
}

// ExtensionSession is a host-first facade for embedders that want to expose a
// formal host API to JS/TS extensions and call those extensions back through a
// single managed session object.
pub struct ExtensionSession {
	host_api vjsx.HostValueBuilder = extension_session_missing_host_api
mut:
	session vjsx.RuntimeSession
}

// Create a script-oriented extension session and install the embedder host API.
pub fn new_script_extension_session(ctx_config vjsx.ContextConfig, runtime_config vjsx.ScriptRuntimeConfig, host_config vjsx.HostApiConfig, host_api vjsx.HostValueBuilder) ExtensionSession {
	mut session := new_script_runtime_session(ctx_config, runtime_config)
	session.context().install_host_api(host_config)
	return ExtensionSession{
		host_api: host_api
		session:  session
	}
}

// Create a fuller Node-style extension session and install the embedder host
// API.
pub fn new_node_extension_session(ctx_config vjsx.ContextConfig, runtime_config vjsx.NodeRuntimeConfig, host_config vjsx.HostApiConfig, host_api vjsx.HostValueBuilder) ExtensionSession {
	mut session := new_node_runtime_session(ctx_config, runtime_config)
	session.context().install_host_api(host_config)
	return ExtensionSession{
		host_api: host_api
		session:  session
	}
}

// Access the managed runtime session.
pub fn (extension ExtensionSession) runtime_session() vjsx.RuntimeSession {
	return extension.session
}

// Access the managed context.
pub fn (extension ExtensionSession) context() &vjsx.Context {
	return extension.session.context()
}

// Install more host globals/modules after creation.
pub fn (extension ExtensionSession) install_host_api(config vjsx.HostApiConfig) {
	extension.session.context().install_host_api(config)
}

// Report whether the managed session has already been closed.
pub fn (extension ExtensionSession) is_closed() bool {
	return extension.session.is_closed()
}

// Run a script or module by extension. `.mjs` and `.mts` use module mode.
pub fn (extension ExtensionSession) run(path string) !vjsx.Value {
	return extension.session.run(path)
}

// Run a file in script mode.
pub fn (extension ExtensionSession) run_script(path string) !vjsx.Value {
	return extension.session.run_script(path)
}

// Run a file in module mode.
pub fn (extension ExtensionSession) run_module(path string) !vjsx.Value {
	return extension.session.run_module(path)
}

// Load a raw module namespace object.
pub fn (extension ExtensionSession) load_module(path string) !vjsx.Value {
	return extension.session.load_module(path)
}

// Import a module and bind the embedder host context to its calls.
pub fn (extension ExtensionSession) import_module(path string) !vjsx.BoundScriptModule {
	return extension.session.import_module_with_host(path, extension.host_api)
}

// Load a plugin and bind the embedder host context to its lifecycle hooks.
pub fn (extension ExtensionSession) load_plugin(path string, hooks vjsx.ScriptPluginHooks) !vjsx.BoundScriptPlugin {
	return extension.session.load_plugin_with_host(path, hooks, extension.host_api)
}

// Inspect extension metadata declared by the JS/TS file itself.
pub fn (extension ExtensionSession) describe_extension(path string) !ExtensionManifest {
	mut module_binding := extension.import_module(path)!
	defer {
		module_binding.close()
	}
	return extension_manifest_from_module(module_binding.path(), module_binding.module_handle())
}

// Load one JS/TS file as a higher-level extension instance with both bound
// lifecycle hooks and bound module export calls.
pub fn (extension ExtensionSession) load_extension(path string, hooks vjsx.ScriptPluginHooks) !ExtensionHandle {
	mut module_binding := extension.import_module(path)!
	manifest := extension_manifest_from_module(module_binding.path(), module_binding.module_handle())!
	resolved_hooks := extension_manifest_apply_hooks(manifest, hooks)
	plugin := extension.session.bind_plugin(module_binding.path(), module_binding.module_handle(),
		resolved_hooks)!
	return ExtensionHandle{
		services: manifest.services.clone()
		module:   module_binding
		plugin:   vjsx.new_bound_script_plugin(extension.host_api, plugin)
	}
}

// Call a named module export with the embedder host context as the first
// argument.
pub fn (extension ExtensionSession) call_module_export(path string, export_name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.session.call_module_export_with_host(path, export_name, extension.host_api,
		...args)
}

// Call a method on an exported object with the embedder host context as the
// first argument.
pub fn (extension ExtensionSession) call_module_method(path string, export_name string, method_name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.session.call_module_method_with_host(path, export_name, method_name,
		extension.host_api, ...args)
}

// Call a method on the default export object with the embedder host context as
// the first argument.
pub fn (extension ExtensionSession) call_default_export_method(path string, method_name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.session.call_default_export_method_with_host(path, method_name, extension.host_api,
		...args)
}

// Close the managed session. Safe to call more than once.
pub fn (mut extension ExtensionSession) close() {
	extension.session.close()
}
