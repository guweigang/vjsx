import os
import runtimejs
import vjsx

fn conformance_profile_surface(mut session vjsx.RuntimeSession) string {
	mut module_handle := session.import_module('./tests/conformance/profile_surface.mjs') or {
		panic(err)
	}
	defer {
		module_handle.close()
	}
	value := module_handle.call_export('profileSurface') or { panic(err) }
	defer {
		value.free()
	}
	return value.to_string()
}

fn test_conformance_profile_surface_matrix() {
	mut node := runtimejs.try_new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{}) or {
		panic(err)
	}
	assert conformance_profile_surface(mut node) == 'object|object|function|function|undefined|undefined'
	node.close()

	mut script := runtimejs.try_new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{}) or { panic(err) }
	assert conformance_profile_surface(mut script) == 'object|object|function|undefined|undefined|undefined'
	script.close()

	mut browser := vjsx.new_runtime_session()
	browser.set_runtime_bridge(runtimejs.runtime_session_bridge())
	runtimejs.try_install_cli_browser_runtime(browser.context()) or { panic(err) }
	assert conformance_profile_surface(mut browser) == 'undefined|object|function|function|object|object'
	browser.close()
}

fn test_conformance_typescript_and_package_exports() {
	root := os.join_path(os.temp_dir(), 'vjsx_conformance_package_${os.getpid()}')
	os.rmdir_all(root) or {}
	package_root := os.join_path(root, 'node_modules', 'vjsx-conformance-pkg')
	os.mkdir_all(package_root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	for name in ['package.json', 'index.mjs', 'feature.mjs'] {
		os.write_file(os.join_path(package_root, name), os.read_file(os.join_path('./tests/conformance/pkg', name)) or { panic(err) }) or {
			panic(err)
		}
	}
	consumer := os.join_path(root, 'package_consumer.mjs')
	os.write_file(consumer, os.read_file('./tests/conformance/package_consumer.mjs') or { panic(err) }) or {
		panic(err)
	}
	mut session := runtimejs.try_new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [root, os.real_path('./tests/conformance')]
	}) or { panic(err) }
	defer {
		session.close()
	}
	mut typed := session.import_module('./tests/conformance/typescript_surface.mts') or { panic(err) }
	typed_value := typed.call_export('typedSum', 19, 23) or { panic(err) }
	assert typed_value.to_int() == 42
	typed_value.free()
	typed.close()

	mut package_module := session.import_module(consumer) or {
		panic(err)
	}
	package_value := package_module.get('packageResult') or { panic(err) }
	assert package_value.to_int() == 42
	package_value.free()
	package_module.close()
}
