#!/usr/bin/env -S v run

import os

const repo_root = os.real_path(os.dir(@FILE))

@[noreturn]
fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn shell_quote(value string) string {
	return "'" + value.replace("'", '\'"\'"\'') + "'"
}

fn shell_join(values []string) string {
	mut quoted := []string{}
	for value in values {
		quoted << shell_quote(value)
	}
	return quoted.join(' ')
}

fn is_vjsx_quickjs_checkout(path string) bool {
	return os.is_file(os.join_path(path, 'quickjs.c')) && os.is_file(os.join_path(path, 'quickjs-c-atomics.h')) && os.read_file(os.join_path(path, 'quickjs.h')) or {
		''
	}.contains('QJS_VERSION_MAJOR')
}

fn ensure_quickjs_path() string {
	script := os.join_path(repo_root, 'scripts', 'ensure-quickjs.sh')
	work_root := os.getenv_opt('VJS_QUICKJS_WORK_ROOT') or { os.getwd() }
	result := os.execute('VJS_QUICKJS_WORK_ROOT=${shell_quote(work_root)} ${shell_quote(script)}')
	if result.exit_code != 0 {
		fail(result.output.trim_space())
	}
	return result.output.trim_space()
}

fn default_v_flags(extra_v_flags string) string {
	trimmed := extra_v_flags.trim_space()
	if trimmed == '' {
		return '-cc clang'
	}
	if trimmed.contains('-cc ') || trimmed.contains('-cc=') || trimmed.ends_with('-cc') {
		return trimmed
	}
	return '-cc clang ${trimmed}'
}

fn run_cli_runner(args []string, quickjs_path string) int {
	vexe := os.getenv_opt('VEXE') or { @VEXE }
	flags_part := '${default_v_flags(os.getenv('VJS_V_FLAGS'))} -d build_quickjs'
	command := 'cd ${shell_quote(repo_root)} && ' + 'VJS_QUICKJS_PATH=${shell_quote(quickjs_path)} ' + 'VJS_REPO_ROOT=${shell_quote(repo_root)} ' + 'VJS_CLI_CWD=${shell_quote(os.getwd())} ' + 'VCACHE=${shell_quote(os.getenv_opt('VCACHE') or {
		'/tmp/vcache'
	})} ' + '${shell_quote(vexe)} ${flags_part} run ./cli_runner_bin ${shell_join(args)} 2>&1'
	result := os.execute(command)
	print(result.output)
	return result.exit_code
}

fn main() {
	mut quickjs_path := os.getenv('VJS_QUICKJS_PATH')
	if quickjs_path == '' {
		quickjs_path = ensure_quickjs_path()
	}
	if quickjs_path == '' || !is_vjsx_quickjs_checkout(quickjs_path) {
		fail('compatible QuickJS source not found. Set VJS_QUICKJS_PATH or let vjsx download its managed checkout.')
	}

	exit(run_cli_runner(os.args[1..], quickjs_path))
}
