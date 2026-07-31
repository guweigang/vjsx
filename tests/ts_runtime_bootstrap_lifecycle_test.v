import os
import runtimejs
import vjsx

fn test_install_typescript_runtime_is_idempotent_per_context() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	runtimejs.install_typescript_runtime(ctx) or { panic(err) }
	runtimejs.install_typescript_runtime(ctx) or { panic(err) }
	ready := ctx.js_global('__vjs_typescript_runtime_ready')
	defer {
		ready.free()
	}
	assert ready.to_bool() == true
}

fn test_typescript_runtime_bootstrap_survives_repeated_context_lifecycles() {
	script_path := os.join_path(@VMODROOT, 'tests', 'ts_repeated_bootstrap_runtime', 'main.mts')
	for index in 0 .. 64 {
		mut session := vjsx.new_runtime_session()
		ctx := session.context()
		value := runtimejs.run_runtime_entry(ctx, script_path, true, script_path + '.vjsbuild') or {
			session.close()
			panic('bootstrap failed on iteration ${index}: ${err.msg()}')
		}
		result := ctx.js_global('__vjsx_repeated_bootstrap_value')
		assert result.to_string() == 'ok:42'
		result.free()
		value.free()
		session.close()
	}
}

fn test_typescript_runtime_uses_embedded_assets_without_vendor_asset_root() {
	asset_root := os.join_path(os.temp_dir(), 'vjsx_empty_asset_root_for_ts_runtime_test')
	os.rmdir_all(asset_root) or {}
	os.mkdir_all(asset_root) or { panic(err) }
	defer {
		os.rmdir_all(asset_root) or {}
	}

	script_path := os.join_path(@VMODROOT, 'tests', 'ts_repeated_bootstrap_runtime', 'main.mts')
	mut session := vjsx.new_runtime_session(vjsx.ContextConfig{
		asset_root: asset_root
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := runtimejs.run_runtime_entry(ctx, script_path, true, script_path +
		'.embedded_assets_build') or { panic(err) }
	defer {
		value.free()
	}
	result := ctx.js_global('__vjsx_repeated_bootstrap_value')
	defer {
		result.free()
	}
	assert result.to_string() == 'ok:42'
}

fn test_interactive_javascript_normalizer_inserts_statement_boundary() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	runtimejs.install_typescript_runtime(ctx) or { panic(err) }
	source := 'foo\n(bar)'
	normalized := runtimejs.normalize_interactive_javascript(ctx, source, '<notebook-cell>.ts') or {
		panic(err)
	}
	assert normalized == 'foo;\n(bar)'
}

fn test_interactive_javascript_normalizer_preserves_existing_boundaries() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	runtimejs.install_typescript_runtime(ctx) or { panic(err) }
	source := 'const rows = [\n  {\n    city: "上海市",\n  },\n]\nrows.length'
	normalized := runtimejs.normalize_interactive_javascript(ctx, source, '<notebook-cell>.ts') or {
		panic(err)
	}
	assert normalized == source

	with_semicolon := '({ value: 1 });\nconsole.log("done")'
	normalized_semicolon := runtimejs.normalize_interactive_javascript(ctx, with_semicolon,
		'<notebook-cell>.ts') or { panic(err) }
	assert normalized_semicolon == with_semicolon
}
