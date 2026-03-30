module runtimejs

import os
import vjsx

fn runtime_module_loader_wrapper_path(temp_entry string) string {
	return os.join_path(os.dir(temp_entry), '__vjsx_loader__.mjs')
}

pub fn load_runtime_module(ctx &vjsx.Context, script_path string, temp_root string) !vjsx.Value {
	install_typescript_runtime(ctx)!
	temp_entry := build_runtime_module_entry(ctx, script_path, true, temp_root)!
	defer {
		if temp_root != '' {
			os.rmdir_all(temp_root) or {}
		}
	}
	wrapper_path := runtime_module_loader_wrapper_path(temp_entry)
	specifier := file_relative_specifier(wrapper_path, temp_entry)
	value := ctx.js_eval('
		import * as __vjsx_module_exports from "${specifier}";
		globalThis.__vjsx_loaded_module = __vjsx_module_exports;
	',
		wrapper_path, vjsx.type_module) or { return err }
	value.free()
	ctx.end()
	global := ctx.js_global()
	defer {
		global.delete('__vjsx_loaded_module')
		global.free()
	}
	namespace := global.get('__vjsx_loaded_module')
	if namespace.is_undefined() || namespace.is_null() {
		namespace.free()
		return error('failed to load module namespace for ${script_path}')
	}
	return namespace
}

pub fn runtime_session_bridge() vjsx.RuntimeSessionBridge {
	return vjsx.RuntimeSessionBridge{
		run:         run_runtime_entry
		load_module: load_runtime_module
	}
}

pub fn new_script_runtime_session(ctx_config vjsx.ContextConfig, runtime_config vjsx.ScriptRuntimeConfig) vjsx.RuntimeSession {
	mut session := vjsx.new_script_runtime_session(ctx_config, runtime_config)
	session.set_runtime_bridge(runtime_session_bridge())
	return session
}

pub fn new_node_runtime_session(ctx_config vjsx.ContextConfig, runtime_config vjsx.NodeRuntimeConfig) vjsx.RuntimeSession {
	mut session := vjsx.new_node_runtime_session(ctx_config, runtime_config)
	session.set_runtime_bridge(runtime_session_bridge())
	return session
}
