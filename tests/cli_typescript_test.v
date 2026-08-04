import os
import tests.cli_test_support

fn test_cli_run_typescript_file() {
	output := os.execute('${cli_test_support.command(false)} ./tests/ts_basic.ts')
	assert output.exit_code == 0
	assert output.output.trim_space() == '42'
}

fn test_cli_run_typescript_module() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_runtime_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/ts_module_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ts module'
	assert !os.exists(output_file)
}

fn test_cli_run_plain_typescript_module_without_emit() {
	output := os.execute('${cli_test_support.command(false)} --module ./tests/ts_plain_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == '1'
}

fn test_cli_run_typescript_module_with_object_literal_methods() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/ts_object_literal_runtime.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'plain:ok'
}

fn test_cli_run_typescript_module_graph() {
	output_file := os.join_path(@VMODROOT, 'tests', '.ts_graph_output.txt')
	os.rm(output_file) or {}
	output := os.execute('${cli_test_support.command(false)} --module ./tests/ts_graph/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'graph ready'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_paths() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_runtime',
		'.tsconfig_runtime_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/tsconfig_runtime/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'path alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_tsconfig_extends() {
	output_file := os.join_path(@VMODROOT, 'tests', 'tsconfig_extends_runtime', 'project',
		'.tsconfig_extends_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/tsconfig_extends_runtime/project/src/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'extends alias works'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_runtime', '.ts_pkg_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/ts_pkg_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'node package'
	assert !os.exists(output_file)
}

fn test_cli_run_typescript_node_package_exports() {
	output_file := os.join_path(@VMODROOT, 'tests', 'ts_pkg_exports_runtime',
		'.ts_pkg_exports_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/ts_pkg_exports_runtime/main.mts')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'exports root + exports feature'
	assert !os.exists(output_file)
}

fn test_cli_run_javascript_node_package_exports() {
	output_file := os.join_path(@VMODROOT, 'tests', 'js_pkg_exports_runtime',
		'.js_pkg_exports_output.txt')
	os.rm(output_file) or {}
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/js_pkg_exports_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'js exports root + js exports feature'
	assert !os.exists(output_file)
}

fn test_cli_run_javascript_node_package_browser_map() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/js_pkg_browser_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'browser build'
}

fn test_cli_run_javascript_commonjs_helper_named_exports() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/js_pkg_commonjs_runtime/main.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'upstream:ok'
}
