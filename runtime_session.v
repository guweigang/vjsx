module vjsx

import os

pub type RuntimeSessionRunFn = fn (&Context, string, bool, string) !Value

pub type RuntimeSessionLoadModuleFn = fn (&Context, string, string) !Value

@[params]
pub struct RuntimeSessionBridge {
pub:
	run         RuntimeSessionRunFn        = runtime_session_bridge_missing_run
	load_module RuntimeSessionLoadModuleFn = runtime_session_bridge_missing_load_module
}

// RuntimeSession owns a Runtime/Context pair so embedders can tear both down
// through one idempotent close path. Prefer this over manual Runtime/Context
// ownership unless you need lower-level control.
pub struct RuntimeSession {
	runtime Runtime
	context &Context
mut:
	closed bool
	bridge RuntimeSessionBridge
}

fn runtime_session_bridge_missing_run(_ctx &Context, _script_path string, _as_module bool, _temp_root string) !Value {
	return error('runtime session bridge is not installed; import runtimejs and call session.set_runtime_bridge(runtimejs.runtime_session_bridge())')
}

fn runtime_session_bridge_missing_load_module(_ctx &Context, _script_path string, _temp_root string) !Value {
	return error('runtime session bridge is not installed; import runtimejs and call session.set_runtime_bridge(runtimejs.runtime_session_bridge())')
}

fn runtime_session_resolve_path(path string) !string {
	resolved := if os.is_abs_path(path) { path } else { os.real_path(path) }
	if !os.exists(resolved) {
		return error('script not found: ${resolved}')
	}
	return resolved
}

fn runtime_session_is_module_path(path string) bool {
	return path.ends_with('.mjs') || path.ends_with('.mts')
}

// Create a managed Runtime/Context pair.
// Example:
// ```v
// mut session := vjsx.new_runtime_session()
// defer {
//   session.close()
// }
// ctx := session.context()
// ```
pub fn new_runtime_session(config ContextConfig) RuntimeSession {
	runtime := new_runtime()
	context := runtime.new_context(config)
	return RuntimeSession{
		runtime: runtime
		context: context
		bridge:  RuntimeSessionBridge{}
	}
}

// Create a managed lightweight script runtime profile.
pub fn new_script_runtime_session(ctx_config ContextConfig, runtime_config ScriptRuntimeConfig) RuntimeSession {
	mut session := new_runtime_session(ctx_config)
	session.context.install_script_runtime(runtime_config)
	return session
}

// Create a managed fuller Node-style runtime profile.
pub fn new_node_runtime_session(ctx_config ContextConfig, runtime_config NodeRuntimeConfig) RuntimeSession {
	mut session := new_runtime_session(ctx_config)
	session.context.install_node_runtime(runtime_config)
	return session
}

// Access the managed context.
pub fn (session RuntimeSession) context() &Context {
	return session.context
}

// Access the managed runtime.
// Most callers should not need this directly.
pub fn (session RuntimeSession) runtime() Runtime {
	return session.runtime
}

// Report whether the session has already been closed.
pub fn (session RuntimeSession) is_closed() bool {
	return session.closed
}

// Install the high-level runtime bridge used for run/load/call helpers.
pub fn (mut session RuntimeSession) set_runtime_bridge(bridge RuntimeSessionBridge) {
	session.bridge = bridge
}

// Run a script or module by extension. `.mjs` and `.mts` use module mode.
pub fn (session RuntimeSession) run(path string) !Value {
	script_path := runtime_session_resolve_path(path)!
	return session.bridge.run(session.context, script_path, runtime_session_is_module_path(script_path),
		'')
}

// Run a file in script mode.
pub fn (session RuntimeSession) run_script(path string) !Value {
	script_path := runtime_session_resolve_path(path)!
	return session.bridge.run(session.context, script_path, false, '')
}

// Run a file in module mode.
pub fn (session RuntimeSession) run_module(path string) !Value {
	script_path := runtime_session_resolve_path(path)!
	return session.bridge.run(session.context, script_path, true, '')
}

// Load a module namespace object so the host can inspect and call exports.
pub fn (session RuntimeSession) load_module(path string) !Value {
	script_path := runtime_session_resolve_path(path)!
	return session.bridge.load_module(session.context, script_path, '')
}

// Load a module namespace into a managed ScriptModule handle.
pub fn (session RuntimeSession) import_module(path string) !ScriptModule {
	exports := session.load_module(path)!
	return ScriptModule{
		ctx:     session.context
		exports: exports
		state:   &ScriptModuleState{}
	}
}

// Load a module namespace into a managed BoundScriptModule handle that reuses
// the same host context object/value for every export call.
pub fn (session RuntimeSession) import_module_with_host(path string, host_api HostValueBuilder) !BoundScriptModule {
	script_path := runtime_session_resolve_path(path)!
	handle := session.import_module(script_path)!
	return BoundScriptModule{
		host_api:    host_api
		script_path: script_path
		module:      handle
	}
}

// Load a module export and call it if it is a function. If the export is a
// value, it can be fetched by calling this helper without args.
pub fn (session RuntimeSession) call_module_export(path string, export_name string, args ...AnyValue) !Value {
	mut module_exports := session.import_module(path)!
	defer {
		module_exports.close()
	}
	export_value := module_exports.get_export(export_name)!
	if export_value.is_function() {
		export_value.free()
		return module_exports.call_export(export_name, ...args)
	}
	if args.len > 0 {
		export_value.free()
		return error('module export is not callable: ${export_name}')
	}
	return export_value
}

// Load a module export and call it with an explicit host context object/value
// as the first argument.
pub fn (session RuntimeSession) call_module_export_with_host(path string, export_name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	mut module_exports := session.import_module(path)!
	defer {
		module_exports.close()
	}
	return module_exports.call_export_with_host(export_name, host_api, ...args)
}

// Load an exported object and call one of its methods.
pub fn (session RuntimeSession) call_module_method(path string, export_name string, method_name string, args ...AnyValue) !Value {
	mut module_exports := session.import_module(path)!
	defer {
		module_exports.close()
	}
	return module_exports.call_export_method(export_name, method_name, ...args)
}

// Load an exported object and call one of its methods with an explicit host
// context object/value as the first argument.
pub fn (session RuntimeSession) call_module_method_with_host(path string, export_name string, method_name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	mut module_exports := session.import_module(path)!
	defer {
		module_exports.close()
	}
	return module_exports.call_export_method_with_host(export_name, method_name, host_api,
		...args)
}

// Call a method on a module's default export object.
pub fn (session RuntimeSession) call_default_export_method(path string, method_name string, args ...AnyValue) !Value {
	return session.call_module_method(path, 'default', method_name, ...args)
}

// Call a method on a module's default export object with an explicit host
// context object/value as the first argument.
pub fn (session RuntimeSession) call_default_export_method_with_host(path string, method_name string, host_api HostValueBuilder, args ...AnyValue) !Value {
	return session.call_module_method_with_host(path, 'default', method_name, host_api,
		...args)
}

// Load a script module into a plugin-style lifecycle handle.
pub fn (session RuntimeSession) load_plugin(path string, hooks ScriptPluginHooks) !ScriptPlugin {
	script_path := runtime_session_resolve_path(path)!
	handle := session.import_module(script_path)!
	return session.bind_plugin(script_path, handle, hooks)
}

// Bind a previously loaded module handle into a plugin-style lifecycle handle.
pub fn (session RuntimeSession) bind_plugin(path string, handle ScriptModule, hooks ScriptPluginHooks) !ScriptPlugin {
	script_path := runtime_session_resolve_path(path)!
	plugin := new_script_plugin(script_path, handle, hooks)
	if hooks.auto_dispose_on_close {
		mut cleanup_plugin := plugin
		session.context.register_host_cleanup(fn [mut cleanup_plugin] () {
			if cleanup_plugin.is_closed() {
				return
			}
			dispose_result := cleanup_plugin.dispose() or {
				cleanup_plugin.module.ctx.js_undefined()
			}
			dispose_result.free()
			cleanup_plugin.close()
		})
	}
	return plugin
}

// Load a script module into a plugin-style lifecycle handle that reuses the
// same host context object/value for every lifecycle call.
pub fn (session RuntimeSession) load_plugin_with_host(path string, hooks ScriptPluginHooks, host_api HostValueBuilder) !BoundScriptPlugin {
	plugin := session.load_plugin(path, hooks)!
	return new_bound_script_plugin(host_api, plugin)
}

// Close the managed Context and Runtime. Safe to call more than once.
pub fn (mut session RuntimeSession) close() {
	if session.closed {
		return
	}
	session.context.free()
	session.runtime.free()
	session.closed = true
}
