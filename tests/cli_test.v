import os

fn test_cli_run_file() {
	output := os.execute('sh ./vjsx ./tests/test.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'test foo'
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
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/crypto/hmac_sign_verify.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '32\ntrue'
}

fn test_cli_browser_runtime_crypto_aes_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/crypto/aes_cbc_encrypt_decrypt.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '16\nhello'
}

fn test_cli_browser_runtime_crypto_pbkdf2_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/crypto/pbkdf2_derive_aes.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ae4d0c95af6b46d32d0adff928f06dd0\nAES-CBC:128'
}

fn test_cli_browser_runtime_crypto_signatures_example() {
	output := os.execute('sh ./vjsx --runtime browser --module ./examples/crypto/signatures.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'Ed25519:64:true\nECDSA:71:true'
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
