import os

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

fn test_cli_run_file() {
	output := os.execute('sh ./vjsx ./tests/test.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'test foo'
}

fn test_cli_run_commonjs_file() {
	output := os.execute('sh ./vjsx ./tests/cjs_runtime.cjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'cjs${os.path_separator}dep-ok\ntrue\ntrue'
}

fn test_cli_run_commonjs_shebang_and_json_file() {
	output := os.execute('sh ./vjsx ./tests/cjs_shebang_runtime.cjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'json-ok'
}

fn test_cli_run_module_example() {
	output := os.execute('sh ./vjsx --module ./examples/js/main.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'hello text\nfoo'
}

fn test_cli_run_with_script_runtime_profile() {
	output := os.execute('sh ./vjsx --runtime script ./tests/script_runtime_profile.mjs arg-one')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\nobject\nfunction\nundefined\narg-one\nexample.com'
}

fn test_cli_run_with_browser_runtime_profile() {
	output := os.execute('sh ./vjsx --runtime browser --module ./tests/browser_runtime_profile.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\nobject\nfunction\nfunction\nfunction\nundefined\nobject'
}

fn test_cli_browser_runtime_crypto_subtle_hmac() {
	output := os.execute('sh ./vjsx --runtime browser --module ./tests/browser_crypto_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'HMAC:SHA-256\nsecret\nfalse\nsign,verify\n32\ntrue\nfalse\ntrue\ntrue\nHMAC:SHA-512\n1024\ntrue\n128\n64\ntrue\nEd25519:Ed25519\npublic:private\ntrue:false\n64\ntrue\nfalse\n32\nEd25519:public\ntrue\nAES-CBC:128\n16\ntrue\ntrue\nAES-CTR:128\n5\ntrue\n16\nPBKDF2:secret\nae4d0c95af6b46d32d0adff928f06dd0\nAES-CBC:128\n16\nHMAC:SHA-512:256\n64\ntrue\nECDSA:P-256\npublic:private\ntrue\ntrue\nfalse\n65\n[object CryptoKey]\n[object SubtleCrypto]'
}

fn test_cli_browser_runtime_crypto_hmac_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/webcrypto/hmac_sign_verify.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '32\ntrue'
}

fn test_cli_browser_runtime_crypto_aes_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/webcrypto/aes_cbc_encrypt_decrypt.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '16\nhello'
}

fn test_cli_browser_runtime_crypto_pbkdf2_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/webcrypto/pbkdf2_derive_aes.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ae4d0c95af6b46d32d0adff928f06dd0\nAES-CBC:128'
}

fn test_cli_browser_runtime_crypto_signatures_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/webcrypto/signatures.mjs')
	assert output.exit_code == 0
	lines := output.output.trim_space().split_into_lines()
	assert lines.len == 2
	assert lines[0] == 'Ed25519:64:true'
	assert lines[1] in ['ECDSA:70:true', 'ECDSA:71:true', 'ECDSA:72:true']
}

fn test_cli_browser_runtime_requires_module() {
	output := os.execute('sh ./vjsx --runtime browser ./tests/browser_runtime_profile.mjs')
	assert output.exit_code != 0
	assert output.output.contains('browser runtime requires module mode')
}

fn test_cli_rejects_unknown_runtime_profile() {
	output := os.execute('sh ./vjsx --runtime hybrid ./tests/test.js')
	assert output.exit_code != 0
	assert output.output.contains('unknown runtime profile: hybrid')
}

fn test_cli_rejects_non_js_input() {
	output := os.execute('sh ./vjsx --module ./tests/cli_runner_test.v')
	assert output.exit_code != 0
	assert output.output.contains('unsupported script type: ./tests/cli_runner_test.v')
}

fn test_cli_run_typescript_file() {
	output := os.execute('sh ./vjsx ./tests/ts_basic.ts')
	assert output.exit_code == 0
	assert output.output.trim_space() == '42'
}

fn test_cli_run_typescript_module() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/ts_module_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ts module'
	assert !os.exists(output_file)
}

fn test_cli_run_plain_typescript_module_without_emit() {
	output := os.execute('sh ./vjsx --module ./tests/ts_plain_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == '1'
}

fn test_cli_run_typescript_module_with_object_literal_methods() {
	output := os.execute('sh ./vjsx --module ./tests/ts_object_literal_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'plain:ok'
}

fn test_cli_run_typescript_module_graph() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_graph_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/ts_graph/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'graph ready'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_paths() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_runtime', '.tsconfig_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/tsconfig_runtime/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'path alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_extends() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_extends_runtime', 'project',
		'.tsconfig_extends_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/tsconfig_extends_runtime/project/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'extends alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_runtime', '.ts_pkg_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/ts_pkg_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'node package'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package_exports() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_exports_runtime', '.ts_pkg_exports_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/ts_pkg_exports_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'exports root + exports feature'
	assert !os.exists(output_file)
}

fn test_cli_run_javascript_node_package_exports() {
	output_file := os.join_path(@VMODROOT, 'tests', 'js_pkg_exports_runtime', '.js_pkg_exports_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/js_pkg_exports_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'js exports root + js exports feature'
	assert !os.exists(output_file)
}

fn test_cli_run_javascript_node_package_browser_map() {
	output := os.execute('sh ./vjsx --module ./tests/js_pkg_browser_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'browser build'
}

fn test_cli_run_javascript_commonjs_helper_named_exports() {
	output := os.execute('sh ./vjsx --module ./tests/js_pkg_commonjs_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'upstream:ok'
}

fn test_cli_example_db_sqlite_basic() {
	db_path := os.join_path(@VMODROOT, 'examples', 'db', '.examples_sqlite_basic.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./examples/db/sqlite_basic.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '1:alice\n3\nalice,bob|bob,carol'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_runtime_features() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_runtime.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_sqlite_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'false\ntrue\nfalse\ntrue\n1\n0\n1\n1\n1\n1\n2\n1:alice\n1:alice\ntrue\n2\ntrue\nalice|bob\n2\n3\n4'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_transaction_helper() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_transaction_runtime.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_sqlite_transaction_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'false\ntrue\nfalse\n2\nrollback-me\nalice,bob'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_statement_helper() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_statement_runtime.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_sqlite_statement_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'sqlite\ntrue\nsqlite\ntrue\nsqlite.Connection{path: /Users/guweigang/Source/vjsx/tests/.host_sqlite_statement_runtime.db, closed: false, inTransaction: false}\nsqlite.Statement{kind: exec, closed: false, sql: insert into users(name) values (?)}\ntrue\ninsert into users(name) values (?)\nexec\nquery\nfalse\n1\n1\n2\n2\n3\n1:alice,2:bob\n1:alice\ntrue\n3\nnull\nalice,bob|bob,carol\ntrue\ntrue\nfalse\ntrue'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_close_lifecycle() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_close_runtime.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_sqlite_close_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\nError:sqlite connection is closed'
	assert !os.exists(db_path)
}

fn test_cli_host_mysql_module_available() {
	output := os.execute('sh ./vjsx --module ./tests/host_mysql_module_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'function'
}

fn test_cli_host_error_runtime_features() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_error_runtime.db')
	os.rm(db_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_error_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'TypeError:options.path must be a string\nTypeError:options.busyTimeout must be a number\nTypeError:params must be an array\nTypeError:each param batch must be an array\nTypeError:params must be an array\nError:sqlite statement is closed\nError:sqlite connection is closed\nTypeError:options object is required\nTypeError:options.port must be a number\nError:mysql support is not built in; rerun with -d vjsx_mysql'
	assert !os.exists(db_path)
}

fn test_cli_host_runtime_features() {
	output_file := os.join_path(@VMODROOT, 'tests', '.host_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'written text\na${os.path_separator}b${os.path_separator}c'
	assert os.read_file(output_file) or { panic(err) } == 'written text'
	os.rm(output_file) or {}
}

fn test_cli_script_runtime_skips_fs_module() {
	output := os.execute('sh ./vjsx --runtime script --module ./tests/host_runtime.mjs')
	assert output.exit_code != 0
	assert output.output.contains("could not load module filename 'fs'")
}

fn test_cli_browser_runtime_skips_fs_module() {
	output := os.execute('sh ./vjsx --runtime browser --module ./tests/host_runtime.mjs')
	assert output.exit_code != 0
	assert output.output.contains("could not load module filename 'fs'")
}

fn test_cli_host_more_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_more_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_more_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\n.host_more_runtime_dir${os.path_separator}nested\nnote.txt'
	assert os.read_file(os.join_path(dir_path, 'nested', 'note.txt')) or { panic(err) } == 'nested text'
	os.rmdir_all(dir_path) or {}
}

fn test_cli_host_fs_path_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_fs_path_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_fs_path_runtime.mjs')
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
	output := os.execute('VJS_PROCESS_MARKER=marker-value sh ./vjsx --module ./tests/host_process_runtime.mjs')
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
	output := os.execute('sh ./vjsx --module ./tests/host_process_more_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'js-value\ntrue\n${expected_node_platform()}\n${expected_node_arch()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
}

fn test_cli_host_process_exit_runtime_features() {
	output := os.execute('sh ./vjsx --module ./tests/host_process_exit_runtime.mjs')
	assert output.exit_code == 7
	assert output.output.trim_space() == ''
}

fn test_cli_host_child_process_runtime_features() {
	output := os.execute('sh ./vjsx --module ./tests/host_child_process_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'inherit-child\nhello-child\nafter-inherit\nafter-ignore\n0\ntrue\nhello-child\ntrue\ntrue\nhello-child\n7\nchild-fail'
}

fn test_cli_host_child_process_async_runtime_features() {
	output := os.execute('sh ./vjsx --module ./tests/host_child_process_async_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'execFile:hello-async\ntrue\nhello-async\ntrue\nexecFile-exit:0\nexecFile-close:0\ntrue\nshell-async\ntrue\nlistenerCount:1\nlistenerCountAfterOff:0\nstdio:true:true:true\nlisteners:1\nemit:ok\nemitReturn:true\nlistenerCountAfterEmit:1\nlistenerCountAfterRemoveAll:0\nspawn:hello-async\nspawn-exit:0\nspawn-close:0\nspawn-shell:shell-spawn\nfork:fork-arg|fork-env|tests\nfork-close:0\npipe:hello-async\nunpipe:true\n5\n\nasync-fail\ntrue\nlive:echo:line-from-stdin\nliveerr:done\nlive-close:0:null\nkill:ready\ntrue\nkill-close:null:SIGTERM'
}

fn test_cli_host_fs_sync_runtime_features() {
	output := os.execute('sh ./vjsx --module ./tests/host_fs_sync_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'sync text\ntrue\ntrue\ncopied.txt,nested,source.txt\nsync text\nfalse'
}

fn test_cli_host_os_runtime_features() {
	output := os.execute('sh ./vjsx --module ./tests/host_os_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\ntrue\ntrue\ntrue\ntrue\n${expected_node_platform()}\n${expected_node_arch()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n${expected_node_endianness()}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
}

fn test_cli_host_next_runtime_features() {
	json_path := os.join_path(@VMODROOT, 'tests', '.host_next.json')
	copy_path := os.join_path(@VMODROOT, 'tests', '.host_next_copy.json')
	os.rm(json_path) or {}
	os.rm(copy_path) or {}
	output := os.execute('sh ./vjsx --module ./tests/host_next_runtime.mjs arg-one arg-two')
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
	output := os.execute('sh ./vjsx --module ./tests/host_rename_warn_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'renamed false true\nrename text'
	assert !os.exists(source_path)
	assert !os.exists(target_path)
}
