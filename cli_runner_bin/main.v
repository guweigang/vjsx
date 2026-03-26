module main

import os
import vjsx
import runtimejs

@[noreturn]
fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn main() {
	file := os.getenv('VJS_SCRIPT_FILE')
	as_module := os.getenv('VJS_AS_MODULE') == '1'
	runtime_profile := os.getenv('VJS_RUNTIME_PROFILE')
	args_file := os.getenv('VJS_ARGS_FILE')
	repo_root := os.getenv('VJS_REPO_ROOT')
	if file == '' || runtime_profile == '' || args_file == '' || repo_root == '' {
		fail('missing VJS runner environment')
	}

	script_path := os.real_path(file)
	if !os.exists(script_path) {
		fail('script not found: ${script_path}')
	}

	script_dir := os.dir(script_path)
	script_parent := os.dir(script_dir)
	script_args := if os.exists(args_file) {
		os.read_lines(args_file) or { fail(err.msg()) }
	} else {
		[]string{}
	}
	mut process_args := [script_path]
	process_args << script_args

	prev_dir := os.getwd()
	os.chdir(script_dir) or { fail(err.msg()) }
	defer {
		os.chdir(prev_dir) or {}
	}

	rt := vjsx.new_runtime()
	defer {
		rt.free()
	}

	ctx := rt.new_context()
	defer {
		ctx.free()
	}

	match runtime_profile {
		'node' {
			ctx.install_node_runtime(
				fs_roots:     [script_dir, script_parent, prev_dir]
				process_args: process_args
			)
		}
		'script' {
			ctx.install_script_runtime(
				fs_roots:     [script_dir, script_parent, prev_dir]
				process_args: process_args
			)
		}
		'browser' {
			runtimejs.install_cli_browser_runtime(ctx,
				repo_root: repo_root
			)
		}
		else {
			fail('unknown runtime profile: ${runtime_profile}')
		}
	}

	value := runtimejs.run_runtime_entry(ctx, script_path, as_module, script_path + '.vjsbuild') or {
		fail(err.msg())
	}
	defer {
		value.free()
	}

	if !value.is_undefined() {
		print(value.to_string())
	}
}
