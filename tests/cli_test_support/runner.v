module cli_test_support

import os
import time

const runner_cache_dir = os.join_path(@VMODROOT, '.cache', 'cli-tests')
const runner_lock_stale_after_seconds = i64(10 * 60)

pub fn command(sqlite bool) string {
	runner := ensure_runner(sqlite)
	quickjs_source_path := resolve_quickjs_path()
	v_cache := os.join_path(runner_cache_dir, 'vcache')
	inner := 'VJS_QUICKJS_PATH=${shell_quote(quickjs_source_path)} VCACHE=${shell_quote(v_cache)} VJS_REPO_ROOT=${shell_quote(@VMODROOT)} exec ${shell_quote(runner)} "\$@"'
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
	recover_stale_runner_lock(lock_dir)
	mut owns_lock := true
	os.mkdir(lock_dir) or { owns_lock = false }
	if owns_lock {
		write_runner_lock_owner(lock_dir)
		build_runner(runner, sqlite) or {
			os.rmdir_all(lock_dir) or {}
			panic(err)
		}
		os.rmdir_all(lock_dir) or {}
		return runner
	}
	wait_for_runner(runner, lock_dir)
	if !runner_is_current(runner) {
		return ensure_runner(sqlite)
	}
	return runner
}

fn recover_stale_runner_lock(lock_dir string) {
	if !os.is_dir(lock_dir) {
		return
	}
	owner_path := os.join_path(lock_dir, 'owner.pid')
	if os.is_file(owner_path) {
		owner_pid := os.read_file(owner_path) or { '' }.trim_space().int()
		if owner_pid > 0 && !runner_lock_owner_is_alive(owner_pid) {
			os.rmdir_all(lock_dir) or {}
			return
		}
	}
	age_seconds := time.now().unix() - os.file_last_mod_unix(lock_dir)
	if age_seconds >= runner_lock_stale_after_seconds {
		os.rmdir_all(lock_dir) or {}
	}
}

fn write_runner_lock_owner(lock_dir string) {
	os.write_file(os.join_path(lock_dir, 'owner.pid'), os.getpid().str()) or {
		os.rmdir_all(lock_dir) or {}
		panic(err)
	}
}

fn runner_lock_owner_is_alive(pid int) bool {
	$if windows {
		result := os.execute('tasklist /FI "PID eq ${pid}" /NH')
		return result.exit_code == 0 && result.output.contains(pid.str())
	} $else {
		return os.execute('kill -0 ${pid}').exit_code == 0
	}
}

fn build_runner(runner string, sqlite bool) ! {
	partial := '${runner}.${os.getpid()}.tmp'
	os.rm(partial) or {}
	quickjs_source_path := resolve_quickjs_path()
	v_cache := os.join_path(runner_cache_dir, 'vcache')
	os.mkdir_all(v_cache) or { panic(err) }
	sqlite_flag := if sqlite { ' -d vjsx_sqlite' } else { '' }
	command := 'cd ${shell_quote(@VMODROOT)} && VJS_QUICKJS_PATH=${shell_quote(quickjs_source_path)} VCACHE=${shell_quote(v_cache)} ${shell_quote(@VEXE)} ${quickjs_build_flags()} -d use_openssl${sqlite_flag}${compiler_flag()} -o ${shell_quote(partial)} ./cli_runner_bin'
	result := os.execute(command)
	if result.exit_code != 0 {
		os.rm(partial) or {}
		return error('failed to build shared CLI test runner:\n${result.output}')
	}
	os.rm(runner) or {}
	os.mv(partial, runner)!
}

fn quickjs_build_flags() string {
	if quickjs_lib_path := os.getenv_opt('VJS_QUICKJS_LIB_PATH') {
		if quickjs_lib_path != '' {
			return '-d link_quickjs'
		}
	}
	return '-d build_quickjs'
}

fn compiler_flag() string {
	if compiler := os.getenv_opt('VJS_V_CC') {
		if compiler != '' {
			return ' -cc ${shell_quote(compiler)}'
		}
	}
	return ''
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
