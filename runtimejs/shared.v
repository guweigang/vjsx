module runtimejs

import os
import vjsx

struct ModuleRewrite {
	from     string
	to       string
	resolved string
}

fn is_local_module_specifier(specifier string) bool {
	return specifier.starts_with('./') || specifier.starts_with('../')
}

fn typescript_runtime_path() string {
	return os.join_path(@VMODROOT, 'thirdparty', 'typescript', 'lib', 'typescript.js')
}

fn run_transpiled_source(ctx &vjsx.Context, source string, script_name string, flag int) !vjsx.Value {
	value := ctx.js_eval(source, script_name, flag)!
	ctx.end()
	return value
}

fn runtime_relative_path(from string, to string) string {
	from_abs := os.abs_path(from)
	to_abs := os.abs_path(to)
	sep := os.path_separator.str()
	from_parts := from_abs.split(sep).filter(it.len > 0)
	to_parts := to_abs.split(sep).filter(it.len > 0)
	mut common := 0
	for common < from_parts.len && common < to_parts.len && from_parts[common] == to_parts[common] {
		common++
	}
	mut parts := []string{}
	for _ in common .. from_parts.len {
		parts << '..'
	}
	for part in to_parts[common..] {
		parts << part
	}
	if parts.len == 0 {
		return '.'
	}
	return parts.join(sep)
}

fn mirrored_runtime_path(root string, source_path string) string {
	normalized := source_path.replace('\\', '/')
	trimmed := if normalized.starts_with('/') { normalized[1..] } else { normalized }
	return os.join_path(root, trimmed)
}

fn file_relative_specifier(from_path string, to_path string) string {
	mut rel := runtime_relative_path(os.dir(from_path), to_path)
	if !rel.starts_with('.') {
		rel = './' + rel
	}
	return rel.replace('\\', '/')
}

fn dom_runtime_module_source_path() string {
	return os.join_path(@VMODROOT, 'web', 'js', 'dom_runtime.js')
}

fn emitted_dom_runtime_module_path(root string) string {
	return os.join_path(root, '__vjs_runtime', 'dom_runtime.js')
}
