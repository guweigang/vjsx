module runtimejs

import os
import time
import vjsx

// CompileProjectBundleOptions controls build-time project graph compilation.
@[params]
pub struct CompileProjectBundleOptions {
pub:
	app_name        string
	runtime_profile string = 'node'
	strip_source    bool
	strip_debug     bool
}

fn sanitize_bundle_app_name(name string) !string {
	trimmed := name.trim_space()
	if trimmed == '' {
		return error('vjsx bundle app name is required')
	}
	mut out := []u8{cap: trimmed.len}
	for ch in trimmed.bytes() {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `-` || ch == `_` || ch == `.` {
			out << ch
		} else {
			out << `-`
		}
	}
	result := out.bytestr().trim('-').trim('.')
	if result == '' || result == '.' || result == '..' {
		return error('invalid vjsx bundle app name: ${name}')
	}
	return result
}

fn collect_bundle_files(root string, mut files []string) ! {
	for entry in os.ls(root)! {
		path := os.join_path(root, entry)
		if os.is_dir(path) {
			collect_bundle_files(path, mut files)!
		} else {
			files << path
		}
	}
}

fn bundle_module_name(app_name string, root string, path string) !string {
	root_normalized := os.real_path(root).replace('\\', '/').trim_right('/')
	path_normalized := os.real_path(path).replace('\\', '/')
	prefix := root_normalized + '/'
	if !path_normalized.starts_with(prefix) {
		return error('emitted bundle module is outside build root: ${path}')
	}
	relative := path_normalized[prefix.len..]
	return 'vjsx-bundle/${app_name}/${relative}'
}

// Compile a statically reachable JS/TS/CommonJS/JSON project graph to a
// self-contained `.vjsx` artifact. Source files are only read at build time.
pub fn compile_project_bundle(ctx &vjsx.Context, entry_path string, options CompileProjectBundleOptions) ![]u8 {
	entry := os.real_path(entry_path)
	if !os.exists(entry) || os.is_dir(entry) {
		return error('bundle entry not found: ${entry}')
	}
	app_name := sanitize_bundle_app_name(if options.app_name == '' {
		os.file_name(entry).all_before_last('.')
	} else {
		options.app_name
	})!
	install_typescript_runtime(ctx)!
	temp_root := os.join_path(os.temp_dir(),
		'vjsx-bundle-${os.getpid()}-${time.now().unix_micro()}')
	defer {
		os.rmdir_all(temp_root) or {}
	}
	emitted_entry := build_runtime_module_entry(ctx, entry, true, temp_root)!
	mut files := []string{}
	collect_bundle_files(temp_root, mut files)!
	files.sort()
	mut modules := []vjsx.BundleSourceModule{cap: files.len}
	mut canonical_entry := ''
	for path in files {
		name := bundle_module_name(app_name, temp_root, path)!
		modules << vjsx.BundleSourceModule{
			name:   name
			source: os.read_file(path)!
		}
		if os.real_path(path) == os.real_path(emitted_entry) {
			canonical_entry = name
		}
	}
	if canonical_entry == '' {
		return error('emitted bundle entry was not found in module graph: ${emitted_entry}')
	}
	return ctx.compile_bundle(modules,
		app_name:        app_name
		entry:           canonical_entry
		runtime_profile: options.runtime_profile
		strip_source:    options.strip_source
		strip_debug:     options.strip_debug
	)
}
