module runtimejs

import os
import vjsx

struct ModuleRewrite {
	from     string
	to       string
	resolved string
}

const node_builtin_module_specifiers = [
	'fs',
	'path',
	'os',
	'http',
	'https',
	'child_process',
	'sqlite',
	'mysql',
]

fn is_local_module_specifier(specifier string) bool {
	return specifier.starts_with('./') || specifier.starts_with('../')
}

fn is_node_builtin_module_specifier(specifier string) bool {
	return specifier in node_builtin_module_specifiers
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
	return mirrored_runtime_path_from(root, source_path, '')
}

fn mirrored_runtime_path_from(root string, source_path string, mirror_base string) string {
	if mirror_base.trim_space() != '' {
		source_abs := os.abs_path(source_path).replace('\\', '/').trim_right('/')
		base_abs := os.abs_path(mirror_base).replace('\\', '/').trim_right('/')
		if source_abs == base_abs {
			return root
		}
		prefix := base_abs + '/'
		if source_abs.starts_with(prefix) {
			return os.join_path(root, source_abs[prefix.len..])
		}
	}
	normalized := source_path.replace('\\', '/')
	mut trimmed := normalized.trim_left('/')
	if trimmed.len >= 2 && trimmed[1] == 58 {
		drive := trimmed[0].ascii_str().to_lower()
		rest := trimmed[2..].trim_left('/')
		trimmed = if rest == '' { '_drive_${drive}' } else { '_drive_${drive}/${rest}' }
	}
	return os.join_path(root, trimmed)
}

fn file_relative_specifier(from_path string, to_path string) string {
	mut rel := runtime_relative_path(os.dir(from_path), to_path)
	if !rel.starts_with('.') {
		rel = './' + rel
	}
	return rel.replace('\\', '/')
}

fn emitted_dom_runtime_module_path(root string) string {
	return os.join_path(root, '__vjs_runtime', 'dom_runtime.js')
}
