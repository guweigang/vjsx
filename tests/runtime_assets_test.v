import os
import vjsx

fn test_eval_runtime_file_uses_context_asset_root() {
	asset_root := os.join_path(os.temp_dir(), 'vjsx_runtime_assets_test')
	os.mkdir_all(os.join_path(asset_root, 'web', 'js')) or { panic(err) }
	defer {
		os.rmdir_all(asset_root) or {}
	}
	os.write_file(os.join_path(asset_root, 'web', 'js', 'test.js'),
		'globalThis.__runtime_asset_value = "asset-ok";') or { panic(err) }

	rt := vjsx.new_runtime()
	defer {
		rt.free()
	}
	ctx := rt.new_context(vjsx.ContextConfig{
		asset_root: asset_root
	})
	defer {
		ctx.free()
	}

	value := ctx.eval_runtime_file('web/js/test.js') or { panic(err) }
	value.free()

	result := ctx.js_global('__runtime_asset_value')
	defer {
		result.free()
	}
	assert result.to_string() == 'asset-ok'
}
