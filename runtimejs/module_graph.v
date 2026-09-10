module runtimejs

import crypto.sha256
import os
import vjsx

fn C.vjsx_quickjs_version() &char

fn module_cache_quickjs_abi() string {
	qjs_version := unsafe { cstring_to_vstring(C.vjsx_quickjs_version()) }
	backend := $if quickjs_legacy ? { 'quickjs' } $else { 'quickjs-ng' }
	endian := $if little_endian { 'le' } $else { 'be' }
	return '${backend}/${qjs_version}/ptr${sizeof(voidptr) * 8}/${endian}/bignum'
}

// ModuleResolution records one statically discoverable dependency edge.
pub struct ModuleResolution {
pub:
	importer  string
	specifier string
	resolved  string
	phase     string
	kind      string
	builtin   bool
}

// ModuleGraphNode is a source file participating in a resolved module graph.
pub struct ModuleGraphNode {
pub:
	path        string
	kind        string
	source_hash string
	line_count  int
	imports     []ModuleResolution
}

// ModuleGraph is the shared resolution contract used by run, check and bundle.
// Nodes and edges are sorted so diagnostics, inspection and cache keys are
// deterministic across platforms.
pub struct ModuleGraph {
pub:
	entry           string
	runtime_profile string
	tsconfig_path   string
	tsconfig_hash   string
	cache_key       string
	nodes           []ModuleGraphNode
}

fn module_source_kind(path string) string {
	lower := path.to_lower()
	if lower.ends_with('.json') {
		return 'json'
	}
	if lower.ends_with('.ts') || lower.ends_with('.mts') || lower.ends_with('.cts') {
		return 'typescript'
	}
	if lower.ends_with('.cjs') || lower.ends_with('.cts') {
		return 'commonjs'
	}
	return 'esm'
}

fn module_resolution_phase(specifier string) string {
	if os.is_abs_path(specifier) || is_local_module_specifier(specifier) {
		return 'filesystem'
	}
	return 'package-exports'
}

fn module_resolution_error(importer string, specifier string, phase string, reason string) IError {
	return error('[module-resolution] importer=${importer} specifier="${specifier}" phase=${phase} reason=${reason}')
}

fn inferred_runtime_profile(ctx &vjsx.Context) string {
	browser := ctx.eval('typeof window === "object" && globalThis.window === globalThis', vjsx.type_global) or { return 'node' }
	is_browser := browser.to_bool()
	browser.free()
	if is_browser {
		return 'browser'
	}
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	if snapshot.matches(.script) && !snapshot.matches(.node) {
		return 'script'
	}
	return 'node'
}

fn collect_module_graph(ctx &vjsx.Context, source_path string, config_json string, mut nodes map[string]ModuleGraphNode) ! {
	canonical := os.real_path(source_path)
	if canonical in nodes {
		return
	}
	if !os.is_file(canonical) {
		return module_resolution_error(source_path, '', 'entry', 'source file does not exist')
	}
	source := os.read_file(canonical)!
	// Reserve the node before descending so cycles terminate.
	nodes[canonical] = ModuleGraphNode{
		path: canonical
		kind: module_source_kind(canonical)
		source_hash: sha256.hexhash(source)
		line_count: source.count('\n') + 1
	}
	mut edges := []ModuleResolution{}
	for specifier in list_module_imports(ctx, canonical)! {
		if is_node_builtin_module_specifier(specifier) {
			edges << ModuleResolution{
				importer: canonical
				specifier: specifier
				resolved: specifier
				phase: 'builtin'
				kind: 'builtin'
				builtin: true
			}
			continue
		}
		phase := module_resolution_phase(specifier)
		resolved := resolve_module_specifier(ctx, canonical, specifier, config_json) or {
			return module_resolution_error(canonical, specifier, phase, err.msg())
		}
		kind := module_source_kind(resolved)
		if kind == 'esm' && !vjsx.is_javascript_file(resolved) {
			return module_resolution_error(canonical, specifier, phase, 'unsupported module type: ${os.file_ext(resolved)}')
		}
		edges << ModuleResolution{
			importer: canonical
			specifier: specifier
			resolved: resolved
			phase: phase
			kind: kind
		}
		if kind != 'json' {
			collect_module_graph(ctx, resolved, config_json, mut nodes)!
		} else if resolved !in nodes {
			json_source := os.read_file(resolved)!
			nodes[resolved] = ModuleGraphNode{
				path: resolved
				kind: 'json'
				source_hash: sha256.hexhash(json_source)
				line_count: json_source.count('\n') + 1
			}
		}
	}
	edges.sort_with_compare(fn (a &ModuleResolution, b &ModuleResolution) int {
		return a.specifier.compare(b.specifier)
	})
	nodes[canonical] = ModuleGraphNode{
		path: canonical
		kind: if is_commonjs_module(ctx, canonical) or { false } {
			'commonjs'
		} else {
			module_source_kind(canonical)
		}
		source_hash: sha256.hexhash(source)
		line_count: source.count('\n') + 1
		imports: edges
	}
}

fn module_graph_key(graph ModuleGraph, config_json string) string {
	mut parts := [
		'vjsx-module-cache/1',
		vjsx.artifact_abi,
		module_cache_quickjs_abi(),
		graph.runtime_profile,
		graph.entry.replace('\\', '/'),
		config_json,
	]
	for node in graph.nodes {
		parts << '${node.path.replace('\\', '/')}\x00${node.kind}\x00${node.source_hash}'
		for edge in node.imports {
			parts << '${edge.specifier}\x00${edge.resolved.replace('\\', '/')}\x00${edge.phase}'
		}
	}
	return sha256.hexhash(parts.join('\n'))
}

// resolve_module_graph resolves the complete statically reachable module graph.
// Static-string dynamic import() and require() are included by the scanner.
pub fn resolve_module_graph(ctx &vjsx.Context, entry_path string, runtime_profile string) !ModuleGraph {
	entry := os.real_path(entry_path)
	if !os.is_file(entry) {
		return module_resolution_error(entry, '', 'entry', 'module entry not found')
	}
	install_typescript_runtime(ctx)!
	config_path := find_tsconfig_path(os.dir(entry))
	config_json := if config_path == '' {
		''
	} else {
		normalize_tsconfig(ctx, config_path, os.read_file(config_path)!)!
	}
	mut by_path := map[string]ModuleGraphNode{}
	collect_module_graph(ctx, entry, config_json, mut by_path)!
	mut paths := by_path.keys()
	paths.sort()
	mut nodes := []ModuleGraphNode{cap: paths.len}
	for path in paths {
		nodes << by_path[path]
	}
	mut graph := ModuleGraph{
		entry: entry
		runtime_profile: runtime_profile
		tsconfig_path: config_path
		tsconfig_hash: if config_json == '' { '' } else { sha256.hexhash(config_json) }
		nodes: nodes
	}
	graph = ModuleGraph{
		...graph
		cache_key: module_graph_key(graph, config_json)
	}
	return graph
}

// default_module_cache_root returns the cross-platform cache location used for
// immutable emitted module graphs.
pub fn default_module_cache_root() string {
	if configured := os.getenv_opt('VJSX_CACHE_DIR') {
		if configured.trim_space() != '' {
			return os.join_path(configured, 'module-graphs')
		}
	}
	// os.temp_dir() is user-scoped on macOS and Windows. Hashing the home path
	// also avoids a shared /tmp cache name on Unix without exposing that path.
	user_key := sha256.hexhash(os.home_dir())[..12]
	return os.join_path(os.temp_dir(), 'vjsx-${user_key}', 'module-graphs')
}
