import os
import vjsx

fn collect_runtime_js_assets(root string, dir string) []string {
	mut assets := []string{}
	for name in os.ls(dir) or { return assets } {
		path := os.join_path(dir, name)
		if os.is_dir(path) {
			assets << collect_runtime_js_assets(root, path)
			continue
		}
		if !name.ends_with('.js') {
			continue
		}
		assets << path[root.len + 1..]
	}
	return assets
}

fn test_embedded_runtime_asset_registry_covers_web_js_assets() {
	root := os.join_path(@VMODROOT, 'web', 'js')
	mut disk_assets := collect_runtime_js_assets(@VMODROOT, root)
	disk_assets << [
		'thirdparty/typescript/lib/typescript.js',
		'thirdparty/typescript/lib/vjs_ts_bootstrap.js',
		'thirdparty/typescript/lib/vjs_ts_commonjs.js',
		'thirdparty/typescript/lib/vjs_ts_resolver.js',
		'thirdparty/typescript/lib/vjs_ts_scan.js',
	]
	mut embedded_assets := vjsx.embedded_runtime_asset_paths()
	disk_assets.sort()
	embedded_assets.sort()
	assert embedded_assets == disk_assets
	for asset in disk_assets {
		assert vjsx.has_embedded_runtime_asset(asset)
		assert vjsx.embedded_runtime_asset_source(asset) or { panic(err) } == os.read_file(os.join_path(@VMODROOT,
			asset)) or { panic(err) }
	}
}

fn test_eval_runtime_file_uses_embedded_asset() {
	rt := vjsx.new_runtime()
	defer {
		rt.free()
	}
	ctx := rt.new_context()
	defer {
		ctx.free()
	}

	value := ctx.eval_runtime_file('web/js/buffer.js', vjsx.type_module) or { panic(err) }
	value.free()

	result := ctx.eval('Buffer.from("asset").toString()') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_string() == 'asset'
}

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

fn test_runtime_asset_module_name_is_stable_virtual_uri() {
	assert vjsx.runtime_asset_module_name('web/js/event.js') or { panic(err) } == 'vjsx://web/js/event.js'
	assert vjsx.runtime_asset_module_name('web/js/fetch/../util.js') or { panic(err) } == 'vjsx://web/js/util.js'
}

fn test_eval_runtime_file_uses_virtual_module_name_for_relative_imports() {
	asset_root := os.join_path(os.temp_dir(), 'vjsx_runtime_virtual_imports_test')
	os.mkdir_all(os.join_path(asset_root, 'web', 'js')) or { panic(err) }
	defer {
		os.rmdir_all(asset_root) or {}
	}
	os.write_file(os.join_path(asset_root, 'web', 'js', 'dep.js'),
		'export const label = "virtual-dep"; globalThis.__runtime_dep_url = import.meta.url;') or {
		panic(err)
	}
	os.write_file(os.join_path(asset_root, 'web', 'js', 'entry.js'),
		'import { label } from "./dep.js"; globalThis.__runtime_virtual_import = label;') or {
		panic(err)
	}

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

	value := ctx.eval_runtime_file('web/js/entry.js', vjsx.type_module) or { panic(err) }
	value.free()

	result := ctx.js_global('__runtime_virtual_import')
	defer {
		result.free()
	}
	assert result.to_string() == 'virtual-dep'

	dep_url := ctx.js_global('__runtime_dep_url')
	defer {
		dep_url.free()
	}
	assert dep_url.to_string() == 'vjsx://web/js/dep.js'
}
