import vjsx

fn test_bundle_links_static_modules_and_returns_entry_namespace() {
	mut compiler := vjsx.new_runtime_session()
	defer {
		compiler.close()
	}
	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/demo/dep.mjs'
			source: 'export const answer = 40;'
		},
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/demo/main.mjs'
			source: 'import { answer } from "./dep.mjs"; export const result = answer + 2;'
		},
	],
		app_name:        'demo'
		entry:           'vjsx-bundle/demo/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }
	info := vjsx.bundle_info(bundle) or { panic(err) }
	assert info.app_name == 'demo'
	assert info.module_count == 2

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

fn test_bundle_rejects_profile_mismatch_before_loading_modules() {
	mut compiler := vjsx.new_runtime_session()
	defer {
		compiler.close()
	}
	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/demo/main.mjs'
			source: 'export const value = 1;'
		},
	],
		app_name:        'demo'
		entry:           'vjsx-bundle/demo/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }
	mut runtime := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{})
	defer {
		runtime.close()
	}
	runtime.context().load_bundle(bundle) or {
		assert err.msg().contains('incompatible runtime profile')
		return
	}
	assert false
}

fn test_bundle_module_state_is_initialized_once_and_reused() {
	mut compiler := vjsx.new_runtime_session()
	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/state/main.mjs'
			source: 'let count = 0; export function next() { return ++count; }'
		},
	],
		app_name:        'state'
		entry:           'vjsx-bundle/state/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	first := app.call_export('next') or { panic(err) }
	defer {
		first.free()
	}
	second := app.call_export('next') or { panic(err) }
	defer {
		second.free()
	}
	assert first.to_int() == 1
	assert second.to_int() == 2
}

fn test_bundle_rejects_corruption_and_unknown_format() {
	mut compiler := vjsx.new_runtime_session()
	defer {
		compiler.close()
	}
	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/check/main.mjs'
			source: 'export const ok = true;'
		},
	],
		app_name:        'check'
		entry:           'vjsx-bundle/check/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }

	mut corrupted := bundle.clone()
	corrupted[corrupted.len - 1] ^= u8(1)
	vjsx.bundle_info(corrupted) or {
		assert err.msg().contains('checksum mismatch')
		mut unknown_format := bundle.clone()
		unknown_format[8] = 2
		vjsx.bundle_info(unknown_format) or {
			assert err.msg().contains('incompatible vjsx bundle format')
			return
		}
		assert false
		return
	}
	assert false
}
