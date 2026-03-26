module runtimejs

import os
import vjsx

fn resolve_local_module(importer_path string, specifier string) !string {
	base := os.join_path(os.dir(importer_path), specifier)
	candidates := [
		base,
		base + '.ts',
		base + '.mts',
		base + '.cts',
		base + '.js',
		base + '.mjs',
		base + '.cjs',
		os.join_path(base, 'index.ts'),
		os.join_path(base, 'index.mts'),
		os.join_path(base, 'index.cts'),
		os.join_path(base, 'index.js'),
		os.join_path(base, 'index.mjs'),
		os.join_path(base, 'index.cjs'),
	]
	for candidate in candidates {
		if os.exists(candidate) && !os.is_dir(candidate) {
			return os.real_path(candidate)
		}
	}
	return error('cannot resolve local module "${specifier}" from ${importer_path}')
}

fn package_name_from_specifier(specifier string) (string, string) {
	parts := specifier.split('/')
	if specifier.starts_with('@') {
		if parts.len < 2 {
			return specifier, ''
		}
		return parts[..2].join('/'), if parts.len > 2 {
			parts[2..].join('/')
		} else {
			''
		}
	}
	return parts[0], if parts.len > 1 {
		parts[1..].join('/')
	} else {
		''
	}
}

fn resolve_package_root_entry(ctx &vjsx.Context, package_root string, subpath string) !string {
	package_json_path := os.join_path(package_root, 'package.json')
	if os.exists(package_json_path) {
		entry := package_entry(ctx, package_json_path, subpath) or { '' }
		if entry != '' {
			resolved := resolve_local_module(os.join_path(package_root, '_entry.js'),
				'./' + entry) or { '' }
			if resolved != '' {
				return resolved
			}
		}
	}
	if subpath != '' {
		return resolve_local_module(os.join_path(package_root, '_entry.js'), './' + subpath)
	}
	return resolve_local_module(os.join_path(package_root, '_entry.js'), './index')
}

fn resolve_self_package_source(package_root string, package_subpath string) !string {
	mut candidates := []string{}
	if package_subpath == '' {
		candidates << os.join_path(package_root, 'src', 'index.ts')
		candidates << os.join_path(package_root, 'src', 'index.mts')
		candidates << os.join_path(package_root, 'src', 'index.js')
		candidates << os.join_path(package_root, 'src', 'index.mjs')
	} else {
		candidates << os.join_path(package_root, 'src', package_subpath + '.ts')
		candidates << os.join_path(package_root, 'src', package_subpath + '.mts')
		candidates << os.join_path(package_root, 'src', package_subpath + '.js')
		candidates << os.join_path(package_root, 'src', package_subpath + '.mjs')
		candidates << os.join_path(package_root, 'src', package_subpath, 'index.ts')
		candidates << os.join_path(package_root, 'src', package_subpath, 'index.mts')
		candidates << os.join_path(package_root, 'src', package_subpath, 'index.js')
		candidates << os.join_path(package_root, 'src', package_subpath, 'index.mjs')
	}
	for candidate in candidates {
		if os.exists(candidate) && !os.is_dir(candidate) {
			return os.real_path(candidate)
		}
	}
	return error('no source entry for self package at ${package_root}')
}

fn path_starts_with(path string, root string) bool {
	path_abs := os.real_path(path)
	root_abs := os.real_path(root)
	if path_abs == root_abs {
		return true
	}
	prefix := root_abs + os.path_separator.str()
	return path_abs.starts_with(prefix)
}

fn should_use_self_package_source(importer_path string, package_root string) bool {
	return path_starts_with(importer_path, os.join_path(package_root, 'src'))
}

fn resolve_self_package(ctx &vjsx.Context, importer_path string, package_name string, package_subpath string) !string {
	mut current := os.dir(importer_path)
	for {
		package_json_path := os.join_path(current, 'package.json')
		if os.exists(package_json_path) && !os.is_dir(package_json_path) {
			if package_name_from_json(ctx, package_json_path) or { '' } == package_name {
				if should_use_self_package_source(importer_path, current) {
					if source_resolved := resolve_self_package_source(current, package_subpath) {
						return source_resolved
					}
				}
				return resolve_package_root_entry(ctx, current, package_subpath)
			}
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return error('no self package match for "${package_name}" from ${importer_path}')
}

fn resolve_node_module(ctx &vjsx.Context, importer_path string, specifier string) !string {
	package_name, package_subpath := package_name_from_specifier(specifier)
	if self_resolved := resolve_self_package(ctx, importer_path, package_name, package_subpath) {
		return self_resolved
	}
	mut current := os.dir(importer_path)
	for {
		package_root := os.join_path(current, 'node_modules', package_name)
		if os.is_dir(package_root) {
			return resolve_package_root_entry(ctx, package_root, package_subpath)
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return error('cannot resolve package "${specifier}" from ${importer_path}')
}

fn resolve_module_specifier(ctx &vjsx.Context, importer_path string, specifier string, config_json string) !string {
	if os.is_abs_path(specifier) {
		if os.exists(specifier) && !os.is_dir(specifier) {
			return os.real_path(specifier)
		}
		return resolve_local_module(importer_path, specifier)
	}
	if is_local_module_specifier(specifier) {
		return resolve_local_module(importer_path, specifier)
	}
	if package_resolved := resolve_node_module(ctx, importer_path, specifier) {
		return package_resolved
	}
	resolved := resolve_ts_module(ctx, importer_path, specifier, config_json) or { '' }
	if resolved != '' && !resolved.ends_with('.d.ts') {
		return os.real_path(resolved)
	}
	return error('cannot resolve module "${specifier}" from ${importer_path}')
}

fn rewrite_module_specifiers(input string, rewrites []ModuleRewrite) string {
	mut output := input
	for rewrite in rewrites {
		output = output.replace('"${rewrite.from}"', '"${rewrite.to}"')
		output = output.replace('\'${rewrite.from}\'', '\'${rewrite.to}\'')
	}
	return output
}
