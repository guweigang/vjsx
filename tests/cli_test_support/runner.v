module cli_test_support

import os
import time

const runner_cache_dir = os.join_path(@VMODROOT, '.cache', 'cli-tests')

pub fn command(sqlite bool) string {
	runner := ensure_runner(sqlite)
	quickjs_source_path := resolve_quickjs_path()
	v_cache := os.join_path(runner_cache_dir, 'vcache')
	inner := 'VJS_QUICKJS_PATH=${shell_quote(quickjs_source_path)} VCACHE=${shell_quote(v_cache)} VJS_REPO_ROOT=${shell_quote(@VMODROOT)} exec ${shell_quote(runner)} "$@"'
	return 'sh -c ${shell_quote(inner)} --'
}

fn ensure_runner(sqlite bool) string {
	os.mkdir_all(runner_cache_dir) or { panic(err) }
	suffix := if sqlite { '-sqlite' } else { '' }
	exe_suffix := $if windows { '.exe' } $else { '' }
	runner := os.join_path(runner_cache_dir, 'vjsx${suffix}${exe_suffix}')
	if runner_is_current(runner) {
		return runner
	}
	lock_dir := runner + '.lock'
	mut owns_lock := true
	os.mkdir(lock_dir) or { owns_lock = false }
	if owns_lock {
		build_runner(runner, sqlite) or {
			os.rmdir(lock_dir) or {}
			panic(err)
		}
		os.rmdir(lock_dir) or {}
		return runner
	}
	wait_for_runner(runner, lock_dir)
	if !runner_is_current(runner) {
		return ensure_runner(sqlite)
	}
	return runner
}

fn build_runner(runner string, sqlite bool) ! {
	partial := '${runner}.${os.getpid()}.tmp'
	os.rm(partial) or {}
	quickjs_source_path := resolve_quickjs_path()
	v_cache := os.join_path(runner_cache_dir, 'vcache')
	os.mkdir_all(v_cache) or { panic(err) }
	sqlite_flag := if sqlite { ' -d vjsx_sqlite' } else { '' }
	command := 'cd ${shell_quote(@VMODROOT)} && VJS_QUICKJS_PATH=${shell_quote(quickjs_source_path)} VCACHE=${shell_quote(v_cache)} ${shell_quote(@VEXE)} -d build_quickjs${sqlite_flag} -o ${shell_quote(partial)} ./cli_runner_bin'
	result := os.execute(command)
	if result.exit_code != 0 {
		os.rm(partial) or {}
		return error('failed to build shared CLI test runner:\n${result.output}')
	}
	os.rm(runner) or {}
	os.mv(partial, runner)!
}

fn resolve_quickjs_path() string {
	if configured := os.getenv_opt('VJS_QUICKJS_PATH') {
		if configured != '' {
			return configured
		}
	}
	result := os.execute('cd ${shell_quote(@VMODROOT)} && ./scripts/ensure-quickjs.sh')
	if result.exit_code != 0 {
		panic('failed to locate QuickJS for CLI tests:\n${result.output}')
	}
	return result.output.trim_space()
}

fn wait_for_runner(runner string, lock_dir string) {
	deadline := time.now().add(2 * time.minute)
	for time.now() < deadline {
		if runner_is_current(runner) {
			return
		}
		if !os.exists(lock_dir) {
			return
		}
		time.sleep(50 * time.millisecond)
	}
	panic('timed out waiting for shared CLI test runner: ${runner}')
}

fn runner_is_current(runner string) bool {
	if !os.is_file(runner) {
		return false
	}
	runner_mtime := os.file_last_mod_unix(runner)
	for path in cli_runner_sources() {
		if os.file_last_mod_unix(path) > runner_mtime {
			return false
		}
	}
	return true
}

fn cli_runner_sources() []string {
	mut sources := os.walk_ext(@VMODROOT, '.v')
	sources << os.walk_ext(os.join_path(@VMODROOT, 'web'), '.js')
	sources << os.walk_ext(os.join_path(@VMODROOT, 'thirdparty', 'typescript', 'lib'), '.js')
	return sources
}

fn shell_quote(value string) string {
	return "'" + value.replace("'", '\'"\'"\'') + "'"
}
