#!/usr/bin/env -S v run

import os
import time

const repo_root = os.real_path(os.dir(@FILE))

@[noreturn]
fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn usage() {
	println('Usage: vjsx run [--module|-m] [--runtime|-r <node|script|browser>] <script.js>')
	println('   or: vjsx [--module|-m] [--runtime|-r <node|script|browser>] <script.js>')
}

fn shell_quote(value string) string {
	return "'" + value.replace("'", "'\"'\"'") + "'"
}

fn default_quickjs_path() string {
	candidate := os.real_path(os.join_path(repo_root, '..', 'quickjs'))
	if os.is_dir(candidate) {
		return candidate
	}
	return ''
}

fn make_args_file(script_args []string) !string {
	path := os.join_path(os.temp_dir(), 'vjsx-args-${os.getpid()}-${time.now().unix_micro()}')
	if script_args.len == 0 {
		os.write_file(path, '')!
		return path
	}
	os.write_file(path, script_args.join_lines() + '\n')!
	return path
}

fn normalize_script_path(script_file string) string {
	if os.is_abs_path(script_file) {
		return script_file
	}
	return os.real_path(script_file)
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

fn run_cli_runner(env map[string]string) int {
	vexe := os.getenv_opt('VEXE') or { @VEXE }
	extra_v_flags := os.getenv('VJS_V_FLAGS').trim_space()
	flags_part := if extra_v_flags == '' {
		'-d build_quickjs'
	} else {
		'${extra_v_flags} -d build_quickjs'
	}
	command := 'cd ${shell_quote(repo_root)} && '
		+ 'VJS_QUICKJS_PATH=${shell_quote(env['VJS_QUICKJS_PATH'])} '
		+ 'VJS_SCRIPT_FILE=${shell_quote(env['VJS_SCRIPT_FILE'])} '
		+ 'VJS_AS_MODULE=${shell_quote(env['VJS_AS_MODULE'])} '
		+ 'VJS_RUNTIME_PROFILE=${shell_quote(env['VJS_RUNTIME_PROFILE'])} '
		+ 'VJS_ARGS_FILE=${shell_quote(env['VJS_ARGS_FILE'])} '
		+ 'VJS_REPO_ROOT=${shell_quote(env['VJS_REPO_ROOT'])} '
		+ 'VCACHE=${shell_quote(env['VCACHE'])} '
		+ '${shell_quote(vexe)} ${flags_part} run ./cli_runner_bin 2>&1'
	result := os.execute(command)
	print(result.output)
	return result.exit_code
}

fn main() {
	mut quickjs_path := os.getenv('VJS_QUICKJS_PATH')
	if quickjs_path == '' {
		quickjs_path = default_quickjs_path()
	}
	if quickjs_path == '' || !os.is_dir(quickjs_path) {
		fail('QuickJS source not found. Set VJS_QUICKJS_PATH to your quickjs checkout.')
	}

	mut args := os.args[1..].clone()
	if args.len > 0 && args[0] == 'run' {
		args = args[1..].clone()
	}

	mut script_file := ''
	mut script_args := []string{}
	mut as_module := false
	mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	mut i := 0
	for i < args.len {
		arg := args[i]
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
				if i + 1 >= args.len {
					fail('missing runtime profile after ${arg}')
				}
				runtime_profile = args[i + 1]
				i++
			}
			'--help', '-h' {
				usage()
				return
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
	if runtime_profile == 'browser' && !as_module {
		fail('browser runtime requires module mode\nuse --module with --runtime browser')
	}
	if script_file == '' {
		fail('missing script path')
	}

	as_module = validate_script_type(script_file, as_module)
	script_path := normalize_script_path(script_file)

	args_file := make_args_file(script_args) or { fail(err.msg()) }
	defer {
		os.rm(args_file) or {}
	}

	mut env := os.environ()
	env['VJS_QUICKJS_PATH'] = quickjs_path
	env['VJS_SCRIPT_FILE'] = script_path
	env['VJS_AS_MODULE'] = if as_module { '1' } else { '0' }
	env['VJS_RUNTIME_PROFILE'] = runtime_profile
	env['VJS_ARGS_FILE'] = args_file
	env['VJS_REPO_ROOT'] = repo_root
	if env['VCACHE'] == '' {
		env['VCACHE'] = '/tmp/vcache'
	}

	exit(run_cli_runner(env))
}
