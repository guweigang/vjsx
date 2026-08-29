import os
import tests.cli_test_support

fn expected_node_platform() string {
	return match os.user_os() {
		'macos' { 'darwin' }
		'windows' { 'win32' }
		else { os.user_os() }
	}
}

fn expected_node_arch() string {
	machine := os.uname().machine.to_lower()
	return match machine {
		'x86_64', 'amd64' {
			'x64'
		}
		'x86', 'i386', 'i686' {
			'ia32'
		}
		'aarch64', 'arm64' {
			'arm64'
		}
		'armv7l', 'armv7', 'armv6l', 'armv6' {
			'arm'
		}
		'ppc64le' {
			'ppc64'
		}
		else {
			if machine == '' {
				'unknown'
			} else {
				machine
			}
		}
	}
}

fn expected_node_endianness() string {
	$if little_endian {
		return 'LE'
	} $else {
		return 'BE'
	}
}

fn test_cli_host_runtime_features() {
	output_file := os.join_path(@VMODROOT, 'tests', '.host_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('${cli_test_support.command(false)} --module ./tests/host_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'written text\na${os.path_separator}b${os.path_separator}c'
	assert os.read_file(output_file) or { panic(err) } == 'written text'
	os.rm(output_file) or {}
}

fn test_cli_node_fs_promises_and_ed25519_crypto_modules() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_node_compat_modules_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'promise fs\nfunction:function:function\ntrue\nprivate:public:ed25519\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
}

fn test_cli_script_runtime_skips_fs_module() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime script --module ./tests/host_runtime.mjs')
	assert output.exit_code != 0
	assert output.output.contains("could not load module filename 'fs'")
}

fn test_cli_browser_runtime_skips_fs_module() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./tests/host_runtime.mjs')
	assert output.exit_code != 0
	assert output.output.contains("could not load module filename 'fs'")
}

fn test_cli_host_more_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_more_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_more_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\n.host_more_runtime_dir${os.path_separator}nested\nnote.txt'
	assert os.read_file(os.join_path(dir_path, 'nested', 'note.txt')) or { panic(err) } == 'nested text'
	os.rmdir_all(dir_path) or {}
}

fn test_cli_host_fs_path_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_fs_path_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_fs_path_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.contains('note.txt')
	assert output.output.contains('.txt')
	assert output.output.contains('true')
	assert output.output.contains('false')
	assert output.output.contains(os.join_path(@VMODROOT, 'tests', '.host_fs_path_runtime_dir',
		'nested', 'note.txt'))
	assert !os.exists(dir_path)
}

fn test_cli_host_process_runtime_features() {
	source_path := os.join_path(@VMODROOT, 'tests', '.host_process_source.txt')
	copy_path := os.join_path(@VMODROOT, 'tests', '.host_process_copy.txt')
	os.rm(source_path) or {}
	os.rm(copy_path) or {}
	os.setenv('VJS_PROCESS_MARKER', 'marker-value', true)
	defer {
		os.unsetenv('VJS_PROCESS_MARKER')
	}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_process_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.contains('true')
	assert output.output.contains('11')
	assert output.output.contains('copy source')
	assert output.output.contains('.host_process_copy.txt')
	assert output.output.contains('marker-value')
	assert !os.exists(source_path)
	assert !os.exists(copy_path)
}

fn test_cli_host_process_more_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_process_more_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'js-value\ntrue\n${expected_node_platform()}\n${expected_node_arch()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
}

fn test_cli_host_process_exit_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_process_exit_runtime.mjs')
	assert output.exit_code == 7
	assert output.output.trim_space() == ''
}

fn test_cli_host_child_process_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_child_process_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'inherit-child\nhello-child\nafter-inherit\nafter-ignore\n0\ntrue\nhello-child\ntrue\ntrue\nhello-child\n7\nchild-fail'
}

fn test_cli_host_child_process_async_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_child_process_async_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'execFile:hello-async\ntrue\nhello-async\ntrue\nexecFile-exit:0\nexecFile-close:0\ntrue\nshell-async\ntrue\nlistenerCount:1\nlistenerCountAfterOff:0\nstdio:true:true:true\nlisteners:1\nemit:ok\nemitReturn:true\nlistenerCountAfterEmit:1\nlistenerCountAfterRemoveAll:0\nspawn:hello-async\nspawn-exit:0\nspawn-close:0\nspawn-shell:shell-spawn\nfork:fork-arg|fork-env|tests\nfork-close:0\npipe:hello-async\nunpipe:true\n5\n\nasync-fail\ntrue\nlive:echo:line-from-stdin\nliveerr:done\nlive-close:0:null\nkill:ready\ntrue\nkill-close:null:SIGTERM'
}

fn test_cli_host_fs_sync_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_fs_sync_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'sync text\ntrue\ntrue\ncopied.txt,nested,source.txt\nsync text\nfalse'
}

fn test_cli_host_binary_compat_runtime_features() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_binary_compat_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\nTypeError\nRangeError\n0,255,1,128\nstring\nexclusive-rejected\nTypeError\ntrue:2,254,3,129\ntrue'
}

fn test_cli_host_os_runtime_features() {
	output := os.execute('${cli_test_support.command(false)} --module ./tests/host_os_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\ntrue\ntrue\ntrue\ntrue\n${expected_node_platform()}\n${expected_node_arch()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n${expected_node_endianness()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
}

fn test_cli_host_next_runtime_features() {
	json_path := os.join_path(@VMODROOT, 'tests', '.host_next.json')
	copy_path := os.join_path(@VMODROOT, 'tests', '.host_next_copy.json')
	os.rm(json_path) or {}
	os.rm(copy_path) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_next_runtime.mjs arg-one arg-two')
	assert output.exit_code == 0
	assert output.output.contains('true')
	assert output.output.contains('7')
	assert output.output.contains('.host_next_copy.json')
	assert output.output.contains('host_next_runtime.mjs|arg-one|arg-two')
	assert !os.exists(json_path)
	assert !os.exists(copy_path)
}

fn test_cli_host_rename_warn_runtime_features() {
	source_path := os.join_path(@VMODROOT, 'tests', '.host_rename_warn_source.txt')
	target_path := os.join_path(@VMODROOT, 'tests', '.host_rename_warn_target.txt')
	os.rm(source_path) or {}
	os.rm(target_path) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_rename_warn_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'renamed false true\nrename text'
	assert !os.exists(source_path)
	assert !os.exists(target_path)
}
