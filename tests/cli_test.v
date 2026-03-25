import os

fn test_cli_run_file() {
	output := os.execute('sh ./vjs ./tests/test.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'test foo'
}

fn test_cli_run_module_example() {
	output := os.execute('sh ./vjs --module ./examples/js/main.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'hello text\nfoo'
}

fn test_cli_rejects_non_js_input() {
	output := os.execute('sh ./vjs --module ./tests/cli_runner_test.v')
	assert output.exit_code != 0
	assert output.output.contains('unsupported script type: ./tests/cli_runner_test.v')
}

fn test_cli_run_typescript_file() {
	output := os.execute('sh ./vjs ./tests/ts_basic.ts')
	assert output.exit_code == 0
	assert output.output.trim_space() == '42'
}

fn test_cli_run_typescript_module() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/ts_module_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ts module'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_module_graph() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_graph_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/ts_graph/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'graph ready'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_paths() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_runtime', '.tsconfig_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/tsconfig_runtime/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'path alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_extends() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_extends_runtime', 'project', '.tsconfig_extends_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/tsconfig_extends_runtime/project/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'extends alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_runtime', '.ts_pkg_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/ts_pkg_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'node package'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package_exports() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_exports_runtime', '.ts_pkg_exports_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/ts_pkg_exports_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'exports root + exports feature'
	assert !os.exists(output_file)
}

fn test_cli_host_runtime_features() {
	output_file := os.join_path(@VMODROOT, 'tests', '.host_runtime_output.txt')
	os.rm(output_file) or {}
	output := os.execute('sh ./vjs --module ./tests/host_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'written text\na${os.path_separator}b${os.path_separator}c'
	assert os.read_file(output_file) or { panic(err) } == 'written text'
	os.rm(output_file) or {}
}

fn test_cli_host_more_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_more_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output := os.execute('sh ./vjs --module ./tests/host_more_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\n.host_more_runtime_dir${os.path_separator}nested\nnote.txt'
	assert os.read_file(os.join_path(dir_path, 'nested', 'note.txt')) or { panic(err) } == 'nested text'
	os.rmdir_all(dir_path) or {}
}

fn test_cli_host_fs_path_runtime_features() {
	dir_path := os.join_path(@VMODROOT, 'tests', '.host_fs_path_runtime_dir')
	os.rmdir_all(dir_path) or {}
	output := os.execute('sh ./vjs --module ./tests/host_fs_path_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.contains('note.txt')
	assert output.output.contains('.txt')
	assert output.output.contains('true')
	assert output.output.contains('false')
	assert output.output.contains(os.join_path(@VMODROOT, 'tests', '.host_fs_path_runtime_dir', 'nested', 'note.txt'))
	assert !os.exists(dir_path)
}

fn test_cli_host_process_runtime_features() {
	source_path := os.join_path(@VMODROOT, 'tests', '.host_process_source.txt')
	copy_path := os.join_path(@VMODROOT, 'tests', '.host_process_copy.txt')
	os.rm(source_path) or {}
	os.rm(copy_path) or {}
	output := os.execute('VJS_PROCESS_MARKER=marker-value sh ./vjs --module ./tests/host_process_runtime.mjs')
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
	output := os.execute('sh ./vjs --module ./tests/host_next_runtime.mjs arg-one arg-two')
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
	output := os.execute('sh ./vjs --module ./tests/host_rename_warn_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'renamed false true\nrename text'
	assert !os.exists(source_path)
	assert !os.exists(target_path)
}
