module runtimejs

import os
import vjsx

fn test_module_graph_contract_cache_invalidation_and_source_mapping() {
	root := os.join_path(os.temp_dir(), 'vjsx_module_graph_${os.getpid()}')
	emit_root := os.join_path(os.temp_dir(), 'vjsx_module_graph_emit_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.rmdir_all(emit_root) or {}
	os.mkdir_all(os.join_path(root, 'node_modules', 'demo')) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
		os.rmdir_all(emit_root) or {}
	}
	os.write_file(os.join_path(root, 'tsconfig.json'), '{"compilerOptions":{"strict":true}}') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'main.mts'), 'import { value } from "./dep.ts"; import data from "./data.json"; import { packageValue } from "demo/feature"; import("./lazy.mjs"); export const result = value + data.value + packageValue;') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'dep.ts'), 'export const value: number = 1;') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'data.json'), '{"value":2}') or { panic(err) }
	os.write_file(os.join_path(root, 'lazy.mjs'), 'export const lazy = true;') or { panic(err) }
	os.write_file(os.join_path(root, 'node_modules', 'demo', 'package.json'), '{"name":"demo","exports":{"./feature":"./feature.cjs"}}') or { panic(err) }
	os.write_file(os.join_path(root, 'node_modules', 'demo', 'feature.cjs'), 'module.exports = { packageValue: 39 };') or { panic(err) }

	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	graph := resolve_module_graph(ctx, os.join_path(root, 'main.mts'), 'node') or {
		panic(err)
	}
	assert graph.nodes.len == 5
	assert graph.tsconfig_path == os.real_path(os.join_path(root, 'tsconfig.json'))
	assert graph.tsconfig_hash != ''
	assert graph.nodes.any(it.kind == 'json')
	assert graph.nodes.any(it.kind == 'commonjs')
	main_node := graph.nodes.filter(it.path.ends_with('main.mts'))[0]
	assert main_node.imports.any(it.specifier == './lazy.mjs')
	assert main_node.imports.any(it.phase == 'package-exports')
	assert graph.cache_key == resolve_module_graph(ctx, os.join_path(root, 'main.mts'), 'node')!.cache_key
	assert graph.cache_key != resolve_module_graph(ctx, os.join_path(root, 'main.mts'), 'script')!.cache_key

	os.write_file(os.join_path(root, 'dep.ts'), 'export const value: number = 2;') or {
		panic(err)
	}
	changed_source := resolve_module_graph(ctx, os.join_path(root, 'main.mts'), 'node')!
	assert graph.cache_key != changed_source.cache_key
	os.write_file(os.join_path(root, 'tsconfig.json'), '{"compilerOptions":{"strict":true,"jsx":"preserve"}}') or { panic(err) }
	changed_config := resolve_module_graph(ctx, os.join_path(root, 'main.mts'), 'node')!
	assert changed_source.cache_key != changed_config.cache_key

	prepare_runtime_module_graph(ctx, changed_config, emit_root, '')!
	dep_node := changed_config.nodes.filter(it.path.ends_with('dep.ts'))[0]
	cjs_node := changed_config.nodes.filter(it.path.ends_with('feature.cjs'))[0]
	emitted_ts := os.read_file(mirrored_runtime_path(emit_root, dep_node.path))!
	emitted_cjs := os.read_file(mirrored_runtime_path(emit_root, cjs_node.path))!
	assert emitted_ts.contains('sourceMappingURL=data:application/json;base64,')
	assert emitted_cjs.contains('sourceMappingURL=data:application/json;base64,')

	generated_cjs := mirrored_runtime_path(emit_root, cjs_node.path)
	mapped := remap_module_error('${generated_cjs}:${commonjs_source_line_offset(cjs_node.imports.len) + 1}:7', emit_root, changed_config, '')
	assert mapped == '${cjs_node.path}:1:7'
}

fn test_module_graph_resolution_diagnostic_has_context() {
	root := os.join_path(os.temp_dir(), 'vjsx_module_graph_error_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	entry := os.join_path(root, 'main.mjs')
	os.write_file(entry, 'import "./missing.js";') or { panic(err) }
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	resolve_module_graph(session.context(), entry, 'node') or {
		assert err.msg().contains('importer=${os.real_path(entry)}')
		assert err.msg().contains('specifier="./missing.js"')
		assert err.msg().contains('phase=filesystem')
		assert err.msg().contains('reason=cannot resolve local module')
		return
	}
	assert false
}

fn test_module_graph_cycle_is_finite_and_cache_key_is_repeatable() {
	root := os.join_path(os.temp_dir(), 'vjsx_module_graph_cycle_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	entry := os.join_path(root, 'a.mjs')
	os.write_file(entry, 'import { b } from "./b.mjs"; export const a = b + 1;') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'b.mjs'), 'import { a } from "./a.mjs"; export const b = (a || 0) + 1;') or { panic(err) }
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	first := resolve_module_graph(session.context(), entry, 'node') or { panic(err) }
	second := resolve_module_graph(session.context(), entry, 'node') or { panic(err) }
	assert first.nodes.len == 2
	assert first.cache_key == second.cache_key
	assert first.nodes.all(it.imports.len == 1)
}
