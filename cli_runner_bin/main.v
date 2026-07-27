module main

import os
import vjsx
import runtimejs

struct CliOptions {
	command          string
	script_file      string
	script_args      []string
	as_module        bool
	runtime_profile  string
	install_specs    []string
	install_registry string
	install_dev      bool
}

@[noreturn]
fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn usage() {
	println('Usage: vjsx [run] [--module|-m] [--runtime|-r <node|script|browser>] <script.js> [args...]')
	println('       vjsx check [--module|-m] [--runtime|-r <node|script|browser>] <script.js> [args...]')
	println('       vjsx check-runtime [--runtime|-r <node|script|browser>]')
	println('       vjsx install [--registry <url>] [--dev] [package[@version]...]')
}

fn read_env_script_args(args_file string) []string {
	if args_file == '' || !os.exists(args_file) {
		return []string{}
	}
	return os.read_lines(args_file) or { fail(err.msg()) }
}

fn validate_script_type(script_file string, as_module bool) bool {
	mut enable_module := as_module
	if script_file.ends_with('.mjs') || script_file.ends_with('.mts') {
		enable_module = true
		return enable_module
	}
	if script_file.ends_with('.js') || script_file.ends_with('.cjs') || script_file.ends_with('.ts')
		|| script_file.ends_with('.cts') {
		return enable_module
	}
	fail('unsupported script type: ${script_file}\nexpected a .js, .mjs, .cjs, .ts, .mts, or .cts file')
	return enable_module
}

fn parse_env_options() ?CliOptions {
	file := os.getenv('VJS_SCRIPT_FILE')
	args_file := os.getenv('VJS_ARGS_FILE')
	if file == '' {
		return none
	}
	return CliOptions{
		command:         'run'
		script_file:     file
		script_args:     read_env_script_args(args_file)
		as_module:       os.getenv('VJS_AS_MODULE') == '1'
		runtime_profile: os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	}
}

fn parse_args(args []string) CliOptions {
	if args.len == 0 {
		if opts := parse_env_options() {
			return opts
		}
		usage()
		fail('missing command or script path')
	}

	mut rest := args.clone()
	mut command := 'run'
	if rest[0] in ['run', 'check', 'check-runtime', 'install'] {
		command = rest[0]
		rest = rest[1..].clone()
	}

	if command == 'install' {
		mut specs := []string{}
		mut registry := os.getenv_opt('VJSX_NPM_REGISTRY') or { 'https://registry.npmjs.org' }
		mut install_dev := false
		mut i := 0
		for i < rest.len {
			arg := rest[i]
			match arg {
				'--registry' {
					if i + 1 >= rest.len {
						fail('missing registry URL after ${arg}')
					}
					registry = rest[i + 1]
					i++
				}
				'--dev' {
					install_dev = true
				}
				'--help', '-h' {
					usage()
					exit(0)
				}
				else {
					if arg.starts_with('-') {
						fail('unknown install flag: ${arg}')
					}
					specs << arg
				}
			}
			i++
		}
		return CliOptions{
			command:          command
			install_specs:    specs
			install_registry: registry
			install_dev:      install_dev
			runtime_profile:  'node'
		}
	}

	mut script_file := ''
	mut script_args := []string{}
	mut as_module := false
	mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	mut i := 0
	for i < rest.len {
		arg := rest[i]
		if script_file != '' {
			script_args << arg
			i++
			continue
		}
		match arg {
			'--module', '-m' {
				as_module = true
			}
			'--runtime', '-r' {
				if i + 1 >= rest.len {
					fail('missing runtime profile after ${arg}')
				}
				runtime_profile = rest[i + 1]
				i++
			}
			'--help', '-h' {
				usage()
				exit(0)
			}
			else {
				if arg.starts_with('-') {
					fail('unknown flag: ${arg}')
				}
				script_file = arg
			}
		}
		i++
	}

	if runtime_profile !in ['node', 'script', 'browser'] {
		fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
	}
	if command == 'check-runtime' {
		return CliOptions{
			command:         command
			runtime_profile: runtime_profile
		}
	}
	if runtime_profile == 'browser' && !as_module {
		fail('browser runtime requires module mode\nuse --module with --runtime browser')
	}
	if script_file == '' {
		fail('missing script path')
	}
	as_module = validate_script_type(script_file, as_module)
	return CliOptions{
		command:         command
		script_file:     script_file
		script_args:     script_args
		as_module:       as_module
		runtime_profile: runtime_profile
	}
}

fn install_runtime(ctx &vjsx.Context, runtime_profile string, script_dir string, script_parent string, prev_dir string, process_args []string) {
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
			runtimejs.install_cli_browser_runtime(ctx)
		}
		else {
			fail('unknown runtime profile: ${runtime_profile}')
		}
	}
}

fn check_runtime(runtime_profile string) !string {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	wd := os.getwd()
	install_runtime(ctx, runtime_profile, wd, os.dir(wd), wd, ['vjsx', 'check-runtime'])
	value := ctx.eval('typeof globalThis === "object"', vjsx.type_global)!
	defer {
		value.free()
	}
	if !value.to_bool() {
		return error('globalThis is not available')
	}
	if runtime_profile == 'browser' {
		browser_value := ctx.eval('typeof window === "object" && typeof self === "object" && typeof fetch === "function" && typeof EventTarget === "function"',
			vjsx.type_global)!
		defer {
			browser_value.free()
		}
		if !browser_value.to_bool() {
			return error('browser runtime profile is incomplete')
		}
		return 'ok\n'
	}
	kind := match runtime_profile {
		'node' { vjsx.RuntimeProfileKind.node }
		'script' { vjsx.RuntimeProfileKind.script }
		else { vjsx.RuntimeProfileKind.unknown }
	}
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	if !snapshot.matches(kind) {
		missing := snapshot.missing_for(kind)
		return error('runtime profile is incomplete: ${missing.join(', ')}')
	}
	return 'ok\n'
}

fn run_script(opts CliOptions) !string {
	script_path := os.real_path(opts.script_file)
	if !os.exists(script_path) {
		fail('script not found: ${script_path}')
	}

	script_dir := os.dir(script_path)
	script_parent := os.dir(script_dir)
	mut process_args := [script_path]
	process_args << opts.script_args

	prev_dir := os.getwd()
	os.chdir(script_dir) or { fail(err.msg()) }
	defer {
		os.chdir(prev_dir) or {}
	}

	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	install_runtime(ctx, opts.runtime_profile, script_dir, script_parent, prev_dir, process_args)

	value := runtimejs.run_runtime_entry(ctx, script_path, opts.as_module,
		script_path + '.vjsbuild') or { fail(err.msg()) }
	defer {
		value.free()
	}

	if !value.is_undefined() {
		return value.to_string()
	}
	return ''
}

fn main() {
	opts := parse_args(os.args[1..])
	output := match opts.command {
		'check-runtime' { check_runtime(opts.runtime_profile) or { fail(err.msg()) } }
		'check' { run_script(opts) or { fail(err.msg()) } }
		'install' { install_packages(opts) or { fail(err.msg()) } }
		else { run_script(opts) or { fail(err.msg()) } }
	}
	if output != '' {
		print(output)
	}
}
