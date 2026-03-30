module runtimejs

import os
import vjsx

fn ensure_runtime_support_files(root string) ! {
	support_path := emitted_dom_runtime_module_path(root)
	os.mkdir_all(os.dir(support_path))!
	os.write_file(support_path, os.read_file(dom_runtime_module_source_path())!)!
}

fn prepend_dom_runtime_import(source string, target_path string, root string) string {
	specifier := file_relative_specifier(target_path, emitted_dom_runtime_module_path(root))
	return 'import "${specifier}";' + '\n' + source + '\n' +
		'if (typeof DOMParser === "function" && globalThis.__vjs_dom_runtime_bootstrap) { globalThis.__vjs_dom_runtime_bootstrap(DOMParser); }'
}

fn strip_shebang(source string) string {
	if source.starts_with('#!') {
		newline := source.index('\n') or { -1 }
		if newline >= 0 {
			return source[newline + 1..]
		}
		return ''
	}
	return source
}

fn render_commonjs_module(source string, rewrites []ModuleRewrite, export_names []string, reexport_targets []string, source_path string) string {
	mut lines := []string{}
	for index, rewrite in rewrites {
		lines << 'import * as __vjs_cjs_import_${index} from "${rewrite.to}";'
	}
	escaped_id := source_path.replace('\\', '\\\\')
	lines << 'globalThis.__vjs_cjs_cache = globalThis.__vjs_cjs_cache || Object.create(null);'
	lines << 'export function __vjs_get_cjs() {'
	lines << '  const key = "${escaped_id}";'
	lines << '  if (!(key in globalThis.__vjs_cjs_cache)) {'
	lines << '    globalThis.__vjs_cjs_cache[key] = { exports: {} };'
	lines << '  }'
	lines << '  return globalThis.__vjs_cjs_cache[key];'
	lines << '}'
	lines << 'const __vjs_require_interop = (mod) => {'
	lines << '  if (mod && typeof mod.__vjs_get_cjs === "function") {'
	lines << '    return mod.__vjs_get_cjs().exports;'
	lines << '  }'
	lines << '  if (mod && typeof mod === "object" && "default" in mod && Object.keys(mod).length === 1) {'
	lines << '    return mod.default;'
	lines << '  }'
	lines << '  return mod;'
	lines << '};'
	lines << 'const require = (id) => {'
	lines << '  switch (id) {'
	for index, rewrite in rewrites {
		lines << '    case "${rewrite.from}": return __vjs_require_interop(__vjs_cjs_import_${index});'
	}
	lines << '    default: throw new Error("Unsupported CommonJS require: " + id + " in ${source_path}");'
	lines << '  }'
	lines << '};'
	lines << 'const module = __vjs_get_cjs();'
	lines << 'const __vjs_exports = module.exports;'
	lines << '((require, module, exports, __filename, __dirname) => {'
	lines << strip_shebang(source)
	lines << '})(require, module, __vjs_exports, "${source_path.replace('\\', '\\\\')}", "${os.dir(source_path).replace('\\',
		'\\\\')}");'
	lines << 'export default module.exports;'
	for name in export_names {
		lines << 'export const ${name} = module.exports.${name};'
	}
	for target in reexport_targets {
		for rewrite in rewrites {
			if rewrite.from == target {
				lines << 'export * from "${rewrite.to}";'
				break
			}
		}
	}
	return lines.join('\n')
}

fn emit_runtime_module_graph(ctx &vjsx.Context, source_path string, root string, config_json string, mut seen map[string]bool) ! {
	if source_path in seen {
		return
	}
	seen[source_path] = true
	target_path := mirrored_runtime_path(root, source_path)
	os.mkdir_all(os.dir(target_path))!
	mut rewrites := []ModuleRewrite{}
	for specifier in list_module_imports(ctx, source_path)! {
		if is_node_builtin_module_specifier(specifier) {
			rewrites << ModuleRewrite{
				from:     specifier
				to:       specifier
				resolved: specifier
			}
			continue
		}
		resolved := resolve_module_specifier(ctx, source_path, specifier, config_json) or { '' }
		if resolved == '' {
			continue
		}
		if resolved.ends_with('.json') {
			target_json_path := mirrored_runtime_path(root, resolved) + '.mjs'
			os.mkdir_all(os.dir(target_json_path))!
			json_text := os.read_file(resolved)!
			os.write_file(target_json_path, prepend_dom_runtime_import('export default ${json_text};',
				target_json_path, root))!
			rewrites << ModuleRewrite{
				from:     specifier
				to:       file_relative_specifier(target_path, target_json_path)
				resolved: resolved
			}
			continue
		}
		if !vjsx.is_typescript_file(resolved) && !vjsx.is_javascript_file(resolved) {
			continue
		}
		emit_runtime_module_graph(ctx, resolved, root, config_json, mut seen)!
		rewrites << ModuleRewrite{
			from:     specifier
			to:       file_relative_specifier(target_path, mirrored_runtime_path(root,
				resolved))
			resolved: resolved
		}
	}
	if vjsx.is_typescript_file(source_path) {
		source := os.read_file(source_path)!
		if typescript_needs_emit(ctx, source_path)! {
			transpiled := transpile_typescript(ctx, source_path, true, config_json)!
			os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(transpiled,
				rewrites), target_path, root))!
		} else {
			os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(source,
				rewrites), target_path, root))!
		}
	} else {
		source := os.read_file(source_path)!
		if vjsx.is_javascript_file(source_path)
			&& (is_commonjs_module(ctx, source_path) or { false }) {
			export_names := list_commonjs_exports(ctx, source_path) or { []string{} }
			reexport_targets := list_commonjs_reexports(ctx, source_path) or { []string{} }
			os.write_file(target_path, prepend_dom_runtime_import(render_commonjs_module(source,
				rewrites, export_names, reexport_targets, source_path), target_path, root))!
		} else {
			os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(source,
				rewrites), target_path, root))!
		}
	}
}

pub fn build_runtime_module_entry(ctx &vjsx.Context, script_path string, as_module bool, temp_root string) !string {
	config_json := load_typescript_config(ctx, script_path) or { '' }
	if !as_module {
		if vjsx.is_javascript_file(script_path) && (is_commonjs_module(ctx, script_path) or { false }) {
			root := if temp_root == '' { script_path + '.vjsbuild' } else { temp_root }
			os.rmdir_all(root) or {}
			os.mkdir_all(root)!
			ensure_runtime_support_files(root)!
			mut seen := map[string]bool{}
			emit_runtime_module_graph(ctx, script_path, root, config_json, mut seen)!
			return mirrored_runtime_path(root, script_path)
		}
		if typescript_needs_emit(ctx, script_path)! {
			return transpile_typescript(ctx, script_path, false, config_json)!
		}
		return os.read_file(script_path)!
	}
	mut root := temp_root
	if root == '' {
		root = script_path + '.vjsbuild'
	}
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	ensure_runtime_support_files(root)!
	mut seen := map[string]bool{}
	emit_runtime_module_graph(ctx, script_path, root, config_json, mut seen)!
	return mirrored_runtime_path(root, script_path)
}

pub fn run_runtime_entry(ctx &vjsx.Context, script_path string, as_module bool, temp_root string) !vjsx.Value {
	script_name := os.file_name(script_path)
	flag := if as_module { vjsx.type_module } else { vjsx.type_global }
	if vjsx.is_typescript_file(script_name) {
		install_typescript_runtime(ctx)!
		if as_module {
			temp_entry := build_runtime_module_entry(ctx, script_path, true, temp_root)!
			defer {
				if temp_root != '' {
					os.rmdir_all(temp_root) or {}
				}
			}
			return ctx.run_file(temp_entry, flag)
		}
		transpiled := build_runtime_module_entry(ctx, script_path, false, temp_root)!
		return run_transpiled_source(ctx, transpiled, script_name, flag)
	}
	if !as_module && vjsx.is_javascript_file(script_name) {
		install_typescript_runtime(ctx)!
		if is_commonjs_module(ctx, script_path)! {
			temp_entry := build_runtime_module_entry(ctx, script_path, true, temp_root)!
			defer {
				if temp_root != '' {
					os.rmdir_all(temp_root) or {}
				}
			}
			return ctx.run_file(temp_entry, vjsx.type_module)
		}
	}
	if as_module && vjsx.is_runtime_module_file(script_name) {
		install_typescript_runtime(ctx)!
		temp_entry := build_runtime_module_entry(ctx, script_path, true, temp_root)!
		defer {
			if temp_root != '' {
				os.rmdir_all(temp_root) or {}
			}
		}
		return ctx.run_file(temp_entry, flag)
	}
	return ctx.run_file(script_path, flag)
}
