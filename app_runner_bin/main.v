module main

import os
import runtimejs
import vjsx

@[noreturn]
fn fail(message string) {
	eprintln('vjsx-app-runner: ${message}')
	exit(1)
}

fn install_app_runtime(ctx &vjsx.Context, profile string, executable_path string) ! {
	wd := os.getwd()
	mut process_args := [executable_path, executable_path]
	if os.args.len > 1 {
		process_args << os.args[1..]
	}
	mut fs_roots := [wd]
	executable_dir := os.dir(executable_path)
	if executable_dir != wd {
		fs_roots << executable_dir
	}
	match profile {
		'node' {
			ctx.install_node_runtime(
				fs_roots:     fs_roots
				process_args: process_args
			)
		}
		'script' {
			ctx.install_script_runtime(
				fs_roots:     fs_roots
				process_args: process_args
			)
		}
		'browser' {
			runtimejs.install_cli_browser_runtime(ctx)
		}
		else {
			return error('unsupported runtime profile: ${profile}')
		}
	}
}

fn run_embedded_app() !int {
	executable_path := os.real_path(os.executable())
	bundle := vjsx.read_appended_bundle(executable_path)!
	info := vjsx.bundle_info(bundle)!
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	install_app_runtime(ctx, info.runtime_profile, executable_path)!
	mut app := ctx.load_bundle(bundle)!
	defer {
		app.close()
	}
	ctx.end()
	exit_code := ctx.eval('typeof process === "object" ? (Number(process.exitCode) || 0) : 0')!
	defer {
		exit_code.free()
	}
	return exit_code.to_int()
}

fn main() {
	exit_code := run_embedded_app() or { fail(err.msg()) }
	if exit_code != 0 {
		exit(exit_code)
	}
}
