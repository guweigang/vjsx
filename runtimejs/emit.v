module runtimejs

import encoding.base64
import json2
import os
import time
import vjsx

struct InlineSourceMap {
	version         int = 3
	file            string
	sources         []string
	sources_content []string @[json: 'sourcesContent']
	names           []string
	mappings        string
}

fn append_identity_source_map(generated string, source string, source_path string, prefix_lines int) string {
	source_lines := source.count('\n') + 1
	mut segments := []string{cap: source_lines}
	for index in 0 .. source_lines {
		segments << if index == 0 { 'AAAA' } else { 'AACA' }
	}
	source_map := InlineSourceMap{
		file: os.file_name(source_path)
		sources: [source_path.replace('\\', '/')]
		sources_content: [source]
		mappings: ';'.repeat(prefix_lines) + segments.join(';')
	}
	encoded := base64.encode_str(json2.encode(source_map, escape_unicode: true))
	return generated + '\n//# sourceMappingURL=data:application/json;base64,${encoded}'
}

fn commonjs_source_line_offset(import_count int) int {
	// One DOM bootstrap import plus the CJS imports, require switch cases and
	// fixed wrapper prelude emitted by render_commonjs_module.
	return 26 + 2 * import_count
}

fn remap_generated_line(line string, generated_path string, source_path string, offset int, source_line_count int) string {
	marker := generated_path + ':'
	position := line.index(marker) or { return line }
	number_start := position + marker.len
	mut number_end := number_start
	for number_end < line.len && line[number_end] >= `0` && line[number_end] <= `9` {
		number_end++
	}
	if number_end == number_start || number_end >= line.len || line[number_end] != `:` {
		return line.replace(generated_path, source_path)
	}
	generated_line := line[number_start..number_end].int()
	original_line := if generated_line > offset { generated_line - offset } else { 1 }
	if original_line > source_line_count {
		return line
	}
	return line[..position] + source_path + ':' + original_line.str() + line[number_end..]
}

fn remap_module_error(message string, root string, graph ModuleGraph, mirror_base string) string {
	mut lines := message.split_into_lines()
	for index, line in lines {
		mut mapped := line
		for node in graph.nodes {
			generated := if node.kind == 'json' {
				mirrored_runtime_path_from(root, node.path, mirror_base) + '.mjs'
			} else {
				mirrored_runtime_path_from(root, node.path, mirror_base)
			}
			offset := if node.kind == 'commonjs' {
				commonjs_source_line_offset(node.imports.len)
			} else {
				// prepend_dom_runtime_import adds one generated line. TypeScript's
				// inline source map supplies richer mappings to downstream tools.
				1
			}
			mapped = remap_generated_line(mapped, generated, node.path, offset, node.line_count)
		}
		lines[index] = mapped
	}
	return lines.join('\n')
}

fn ensure_runtime_support_files(root string) ! {
	support_path := emitted_dom_runtime_module_path(root)
	os.mkdir_all(os.dir(support_path))!
	os.write_file(support_path, vjsx.embedded_runtime_asset_source('web/js/dom_runtime.js')!)!
}

fn prepend_dom_runtime_import(source string, target_path string, root string) string {
	specifier := file_relative_specifier(target_path, emitted_dom_runtime_module_path(root))
	return 'import "${specifier}";' + '\n' + source + '\n' + 'if (typeof DOMParser === "function" && globalThis.__vjs_dom_runtime_bootstrap) { globalThis.__vjs_dom_runtime_bootstrap(DOMParser); }'
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
	source_prefix_lines := lines.len
	lines << strip_shebang(source)
	lines << '})(require, module, __vjs_exports, "${source_path.replace('\\', '\\\\')}", "${os.dir(source_path).replace('\\', '\\\\')}");'
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
	return append_identity_source_map(lines.join('\n'), strip_shebang(source), source_path, source_prefix_lines)
}

fn graph_node_rewrites(node ModuleGraphNode, root string, mirror_base string) []ModuleRewrite {
	mut rewrites := []ModuleRewrite{cap: node.imports.len}
	for edge in node.imports {
		rewrites << ModuleRewrite{
			from: edge.specifier
			to: if edge.builtin {
				edge.specifier
			} else if edge.kind == 'json' {
				file_relative_specifier(mirrored_runtime_path_from(root, node.path, mirror_base), mirrored_runtime_path_from(root, edge.resolved, mirror_base) + '.mjs')
			} else {
				file_relative_specifier(mirrored_runtime_path_from(root, node.path, mirror_base), mirrored_runtime_path_from(root, edge.resolved, mirror_base))
			}
			resolved: edge.resolved
		}
	}
	return rewrites
}

fn emit_resolved_module_graph(ctx &vjsx.Context, graph ModuleGraph, root string, mirror_base string, config_json string) ! {
	for node in graph.nodes {
		source_path := node.path
		target_path := if node.kind == 'json' {
			mirrored_runtime_path_from(root, source_path, mirror_base) + '.mjs'
		} else {
			mirrored_runtime_path_from(root, source_path, mirror_base)
		}
		os.mkdir_all(os.dir(target_path))!
		if node.kind == 'json' {
			json_text := os.read_file(source_path)!
			os.write_file(target_path, prepend_dom_runtime_import('export default ${json_text};', target_path, root))!
			continue
		}
		rewrites := graph_node_rewrites(node, root, mirror_base)
		if vjsx.is_typescript_file(source_path) {
			source := strip_shebang(os.read_file(source_path)!)
			if typescript_needs_emit(ctx, source_path)! {
				transpiled := strip_shebang(transpile_typescript(ctx, source_path, true, config_json)!)
				os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(transpiled, rewrites), target_path, root))!
			} else {
				os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(source, rewrites), target_path, root))!
			}
		} else {
			source := strip_shebang(os.read_file(source_path)!)
			if node.kind == 'commonjs' {
				export_names := list_commonjs_exports(ctx, source_path) or { []string{} }
				reexport_targets := list_commonjs_reexports(ctx, source_path) or { []string{} }
				os.write_file(target_path, prepend_dom_runtime_import(render_commonjs_module(source, rewrites, export_names, reexport_targets, source_path), target_path, root))!
			} else {
				os.write_file(target_path, prepend_dom_runtime_import(rewrite_module_specifiers(source, rewrites), target_path, root))!
			}
		}
	}
}

fn module_graph_cache_path(graph ModuleGraph) string {
	return os.join_path(default_module_cache_root(), graph.cache_key)
}

fn prepare_runtime_module_graph(ctx &vjsx.Context, graph ModuleGraph, requested_root string, mirror_base string) !string {
	root := if requested_root == '' { module_graph_cache_path(graph) } else { requested_root }
	ready := os.join_path(root, '.complete')
	if requested_root == '' && os.is_file(ready) {
		return root
	}
	mut build_root := root
	if requested_root == '' {
		os.mkdir_all(os.dir(root))!
		build_root = '${root}.${os.getpid()}.${time.now().unix_micro()}.tmp'
	} else {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(build_root)!
	defer {
		if build_root != root {
			os.rmdir_all(build_root) or {}
		}
	}
	ensure_runtime_support_files(build_root)!
	config_json := if graph.tsconfig_path == '' {
		''
	} else {
		normalize_tsconfig(ctx, graph.tsconfig_path, os.read_file(graph.tsconfig_path)!)!
	}
	emit_resolved_module_graph(ctx, graph, build_root, mirror_base, config_json)!
	os.write_file(os.join_path(build_root, '.complete'), graph.cache_key)!
	if build_root != root {
		os.mv(build_root, root) or {
			if !os.is_file(ready) {
				return err
			}
		}
	}
	return root
}

fn run_resolved_runtime_module(ctx &vjsx.Context, script_path string, flag int, temp_root string) !vjsx.Value {
	graph := resolve_module_graph(ctx, script_path, inferred_runtime_profile(ctx))!
	root := prepare_runtime_module_graph(ctx, graph, temp_root, '')!
	emitted_entry := mirrored_runtime_path(root, graph.entry)
	return ctx.run_file(emitted_entry, flag) or {
		return error(remap_module_error(err.msg(), root, graph, ''))
	}
}

pub fn build_runtime_module_entry(ctx &vjsx.Context, script_path string, as_module bool, temp_root string) !string {
	config_json := load_typescript_config(ctx, script_path) or { '' }
	if !as_module {
		if vjsx.is_javascript_file(script_path) && (is_commonjs_module(ctx, script_path) or {
			false
		}) {
			graph := resolve_module_graph(ctx, script_path, inferred_runtime_profile(ctx))!
			root := prepare_runtime_module_graph(ctx, graph, temp_root, '')!
			return mirrored_runtime_path(root, script_path)
		}
		if typescript_needs_emit(ctx, script_path)! {
			return transpile_typescript(ctx, script_path, false, config_json)!
		}
		return os.read_file(script_path)!
	}
	graph := resolve_module_graph(ctx, script_path, inferred_runtime_profile(ctx))!
	root := prepare_runtime_module_graph(ctx, graph, temp_root, '')!
	return mirrored_runtime_path(root, script_path)
}

fn build_runtime_module_entry_with_mirror_base(ctx &vjsx.Context, script_path string, as_module bool, temp_root string, mirror_base string) !string {
	config_json := load_typescript_config(ctx, script_path) or { '' }
	if !as_module {
		if vjsx.is_javascript_file(script_path) && (is_commonjs_module(ctx, script_path) or {
			false
		}) {
			graph := resolve_module_graph(ctx, script_path, inferred_runtime_profile(ctx))!
			root := prepare_runtime_module_graph(ctx, graph, temp_root, mirror_base)!
			return mirrored_runtime_path_from(root, script_path, mirror_base)
		}
		if typescript_needs_emit(ctx, script_path)! {
			return transpile_typescript(ctx, script_path, false, config_json)!
		}
		return os.read_file(script_path)!
	}
	graph := resolve_module_graph(ctx, script_path, inferred_runtime_profile(ctx))!
	root := prepare_runtime_module_graph(ctx, graph, temp_root, mirror_base)!
	return mirrored_runtime_path_from(root, script_path, mirror_base)
}

pub fn run_runtime_entry(ctx &vjsx.Context, script_path string, as_module bool, temp_root string) !vjsx.Value {
	script_name := os.file_name(script_path)
	flag := if as_module { vjsx.type_module } else { vjsx.type_global }
	if vjsx.is_typescript_file(script_name) {
		install_typescript_runtime(ctx)!
		if as_module {
			defer {
				if temp_root != '' {
					os.rmdir_all(temp_root) or {}
				}
			}
			return run_resolved_runtime_module(ctx, script_path, flag, temp_root)
		}
		transpiled := build_runtime_module_entry(ctx, script_path, false, temp_root)!
		return run_transpiled_source(ctx, transpiled, script_name, flag)
	}
	if !as_module && vjsx.is_javascript_file(script_name) {
		install_typescript_runtime(ctx)!
		if is_commonjs_module(ctx, script_path)! {
			defer {
				if temp_root != '' {
					os.rmdir_all(temp_root) or {}
				}
			}
			return run_resolved_runtime_module(ctx, script_path, vjsx.type_module, temp_root)
		}
	}
	if as_module && vjsx.is_runtime_module_file(script_name) {
		install_typescript_runtime(ctx)!
		defer {
			if temp_root != '' {
				os.rmdir_all(temp_root) or {}
			}
		}
		return run_resolved_runtime_module(ctx, script_path, flag, temp_root)
	}
	return ctx.run_file(script_path, flag)
}

fn package_runtime_mirror_base(package_root string) string {
	abs_path := os.abs_path(package_root)
	parts := abs_path.split(os.path_separator)
	for offset in 0 .. parts.len {
		index := parts.len - 1 - offset
		if parts[index] == 'node_modules' && index > 0 {
			return parts[..index].join(os.path_separator)
		}
	}
	return package_root
}

// Check the package's default runtime entry and its statically reachable module
// graph without evaluating package code. An empty entry means that the package
// has no importable default entry, which is not by itself an install failure.
pub fn check_runtime_package_entry(ctx &vjsx.Context, package_root string, temp_root string) !string {
	install_typescript_runtime(ctx)!
	entry := resolve_package_root_entry(ctx, package_root, '') or { return '' }
	emitted_entry := build_runtime_module_entry_with_mirror_base(ctx, entry, true, temp_root, package_runtime_mirror_base(package_root))!
	defer {
		if temp_root != '' {
			os.rmdir_all(temp_root) or {}
		}
	}
	ctx.compile_module_file(emitted_entry)!
	return entry
}

// check_runtime_module_graph resolves and compiles an entry and all of its
// static dependencies without evaluating user code. It is the machine-check
// path used by the CLI and shares the same graph and emitted cache as runtime.
pub fn check_runtime_module_graph(ctx &vjsx.Context, entry_path string, runtime_profile string) !ModuleGraph {
	graph := resolve_module_graph(ctx, entry_path, runtime_profile)!
	root := prepare_runtime_module_graph(ctx, graph, '', '')!
	emitted_entry := mirrored_runtime_path(root, graph.entry)
	ctx.compile_module_file(emitted_entry)!
	return graph
}
