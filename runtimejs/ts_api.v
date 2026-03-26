module runtimejs

import os
import vjsx

fn normalize_tsconfig(ctx &vjsx.Context, config_path string, config_text string) !string {
	normalize_fn := ctx.js_global('__vjs_normalize_tsconfig')
	defer {
		normalize_fn.free()
	}
	if normalize_fn.is_undefined() {
		return error('TypeScript config parser is not installed')
	}
	output := ctx.call(normalize_fn, config_text, config_path)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn transpile_typescript(ctx &vjsx.Context, script_path string, as_module bool, config_json string) !string {
	source := os.read_file(script_path)!
	transpile_fn := ctx.js_global('__vjs_transpile_typescript')
	defer {
		transpile_fn.free()
	}
	if transpile_fn.is_undefined() {
		return error('TypeScript transpiler is not installed')
	}
	output := ctx.call(transpile_fn, source, script_path, as_module, config_json)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn list_module_imports(ctx &vjsx.Context, script_path string) ![]string {
	source := os.read_file(script_path)!
	list_fn := ctx.js_global('__vjs_list_module_imports')
	defer {
		list_fn.free()
	}
	if list_fn.is_undefined() {
		return error('TypeScript import scanner is not installed')
	}
	output := ctx.call(list_fn, source, script_path)!
	defer {
		output.free()
	}
	return output.to_string().split('\n').filter(it.len > 0)
}

fn typescript_needs_emit(ctx &vjsx.Context, script_path string) !bool {
	source := os.read_file(script_path)!
	check_fn := ctx.js_global('__vjs_typescript_needs_emit')
	defer {
		check_fn.free()
	}
	if check_fn.is_undefined() {
		return error('TypeScript emit detector is not installed')
	}
	output := ctx.call(check_fn, source, script_path)!
	defer {
		output.free()
	}
	return output.to_bool()
}

fn is_commonjs_module(ctx &vjsx.Context, script_path string) !bool {
	source := os.read_file(script_path)!
	check_fn := ctx.js_global('__vjs_is_commonjs')
	defer {
		check_fn.free()
	}
	if check_fn.is_undefined() {
		return error('CommonJS detector is not installed')
	}
	output := ctx.call(check_fn, source)!
	defer {
		output.free()
	}
	return output.to_bool()
}

fn list_commonjs_exports(ctx &vjsx.Context, script_path string) ![]string {
	source := os.read_file(script_path)!
	list_fn := ctx.js_global('__vjs_list_commonjs_exports')
	defer {
		list_fn.free()
	}
	if list_fn.is_undefined() {
		return error('CommonJS export scanner is not installed')
	}
	output := ctx.call(list_fn, source)!
	defer {
		output.free()
	}
	return output.to_string().split('\n').filter(it.len > 0)
}

fn list_commonjs_reexports(ctx &vjsx.Context, script_path string) ![]string {
	source := os.read_file(script_path)!
	list_fn := ctx.js_global('__vjs_list_commonjs_reexports')
	defer {
		list_fn.free()
	}
	if list_fn.is_undefined() {
		return error('CommonJS re-export scanner is not installed')
	}
	output := ctx.call(list_fn, source)!
	defer {
		output.free()
	}
	return output.to_string().split('\n').filter(it.len > 0)
}

fn resolve_ts_module(ctx &vjsx.Context, importer_path string, specifier string, config_json string) !string {
	resolve_fn := ctx.js_global('__vjs_resolve_ts_module')
	defer {
		resolve_fn.free()
	}
	if resolve_fn.is_undefined() {
		return error('TypeScript resolver is not installed')
	}
	output := ctx.call(resolve_fn, specifier, importer_path, config_json)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn package_entry(ctx &vjsx.Context, package_json_path string, subpath string) !string {
	text := os.read_file(package_json_path)!
	entry_fn := ctx.js_global('__vjs_package_entry')
	defer {
		entry_fn.free()
	}
	if entry_fn.is_undefined() {
		return error('package entry helper is not installed')
	}
	output := ctx.call(entry_fn, text, subpath)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn package_name_from_json(ctx &vjsx.Context, package_json_path string) !string {
	text := os.read_file(package_json_path)!
	name_fn := ctx.js_global('__vjs_package_name')
	defer {
		name_fn.free()
	}
	if name_fn.is_undefined() {
		return error('package name helper is not installed')
	}
	output := ctx.call(name_fn, text)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn find_tsconfig_path(start_dir string) string {
	mut current := os.real_path(start_dir)
	for {
		candidate := os.join_path(current, 'tsconfig.json')
		if os.exists(candidate) && !os.is_dir(candidate) {
			return candidate
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return ''
}

fn load_typescript_config(ctx &vjsx.Context, script_path string) !string {
	config_path := find_tsconfig_path(os.dir(script_path))
	if config_path == '' {
		return ''
	}
	return normalize_tsconfig(ctx, config_path, os.read_file(config_path)!)
}
