import os
import runtimejs
import vjsx

fn test_project_bundle_transpiles_typescript_and_json_without_runtime_sources() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.mts'),
		'import { add } from "./dep.ts"; import data from "./data.json"; export const result = add(data.value, 2);') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'dep.ts'),
		'export function add(a: number, b: number): number { return a + b; }') or { panic(err) }
	os.write_file(os.join_path(root, 'data.json'), '{"value":40}') or { panic(err) }

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.mts'),
		app_name:        'typed-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }
	assert !os.exists(root)

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}

fn test_project_bundle_preserves_commonjs_require_and_exports() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_cjs_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.cjs'),
		'const helper = require("./helper.cjs"); module.exports = { result: helper.add(40, 2) };') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'helper.cjs'),
		'module.exports = { add(a, b) { return a + b; } };') or { panic(err) }

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.cjs'),
		app_name:        'cjs-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}

fn test_project_bundle_includes_static_node_modules_dependencies() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_package_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	package_root := os.join_path(root, 'node_modules', 'answer-package')
	os.mkdir_all(package_root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.mts'),
		'import { answer } from "answer-package"; export const result = answer;') or { panic(err) }
	os.write_file(os.join_path(package_root, 'package.json'),
		'{"name":"answer-package","version":"1.0.0","type":"module","exports":"./index.js"}') or {
		panic(err)
	}
	os.write_file(os.join_path(package_root, 'index.js'), 'export const answer = 42;') or {
		panic(err)
	}

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.mts'),
		app_name:        'package-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}
