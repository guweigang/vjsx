import os
import tests.cli_test_support

fn test_cli_help_and_version_commands() {
	version_output := os.execute('${cli_test_support.command(false)} --version')
	assert version_output.exit_code == 0
	assert version_output.output.trim_space().starts_with('vjsx ')
	version_command_output := os.execute('${cli_test_support.command(false)} version')
	assert version_command_output.exit_code == 0
	assert version_command_output.output == version_output.output
	help_output := os.execute('${cli_test_support.command(false)} --help')
	assert help_output.exit_code == 0
	assert help_output.output.contains('vjsx capabilities [--runtime|-r <node|script|browser>]')
	assert help_output.output.contains('vjsx repair [--registry <url>] [package...]')
	assert help_output.output.contains('Compile command:')
	assert help_output.output.contains('--entry-only          Required in this release.')
	assert help_output.output.contains('-o, --output <file>')
	assert help_output.output.contains('Loading preserves module.exports')
	assert help_output.output.contains('ctx.load_bytecode(bytecode)')
	assert help_output.output.contains('Load only trusted bytecode.')
	assert help_output.output.contains('Runtime profiles:')
}

fn test_cli_repair_and_remove_package_graph() {
	repair_root := os.join_path(os.temp_dir(), 'vjsx_cli_repair_test_${os.getpid()}')
	os.rmdir_all(repair_root) or {}
	defer {
		os.rmdir_all(repair_root) or {}
	}
	workspace_root := os.join_path(repair_root, 'packages', 'local-package')
	os.mkdir_all(workspace_root) or { panic(err) }
	os.write_file(os.join_path(repair_root, 'package.json'),
		'{"name":"repair-root","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"local-package":"workspace:*"}}') or {
		panic(err)
	}
	os.write_file(os.join_path(repair_root, 'package-lock.json'),
		'{"name":"repair-root","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"repair-root","version":"1.0.0","dependencies":{"local-package":"workspace:*"}},"node_modules/local-package":{"version":"1.0.0","link":true}}}') or {
		panic(err)
	}
	os.write_file(os.join_path(workspace_root, 'package.json'),
		'{"name":"local-package","version":"1.0.0","type":"module","exports":"./index.js"}') or {
		panic(err)
	}
	os.write_file(os.join_path(workspace_root, 'index.js'), 'export const value = 42;') or {
		panic(err)
	}
	repair_output := os.execute('cd ${repair_root} && ${cli_test_support.command(false)} repair')
	assert repair_output.exit_code == 0
	assert repair_output.output.contains('repaired 1 package(s)')
	assert os.is_link(os.join_path(repair_root, 'node_modules', 'local-package'))

	remove_root := os.join_path(os.temp_dir(), 'vjsx_cli_remove_graph_test_${os.getpid()}')
	os.rmdir_all(remove_root) or {}
	defer {
		os.rmdir_all(remove_root) or {}
	}
	for name in ['a', 'b', 'c'] {
		package_root := os.join_path(remove_root, 'node_modules', name)
		os.mkdir_all(package_root) or { panic(err) }
		os.write_file(os.join_path(package_root, 'package.json'),
			'{"name":"${name}","version":"1.0.0"}') or { panic(err) }
	}
	os.write_file(os.join_path(remove_root, 'package.json'),
		'{"name":"remove-root","version":"1.0.0","dependencies":{"a":"1.0.0","c":"1.0.0"}}') or {
		panic(err)
	}
	os.write_file(os.join_path(remove_root, 'package-lock.json'),
		'{"name":"remove-root","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"remove-root","version":"1.0.0","dependencies":{"a":"1.0.0","c":"1.0.0"}},"node_modules/a":{"version":"1.0.0","dependencies":{"b":"1.0.0"}},"node_modules/b":{"version":"1.0.0"},"node_modules/c":{"version":"1.0.0"}}}') or {
		panic(err)
	}
	remove_output := os.execute('cd ${remove_root} && ${cli_test_support.command(false)} remove a')
	assert remove_output.exit_code == 0
	assert !os.exists(os.join_path(remove_root, 'node_modules', 'a'))
	assert !os.exists(os.join_path(remove_root, 'node_modules', 'b'))
	assert os.exists(os.join_path(remove_root, 'node_modules', 'c'))
	lock_text := os.read_file(os.join_path(remove_root, 'package-lock.json')) or { panic(err) }
	assert !lock_text.contains('node_modules/a')
	assert !lock_text.contains('node_modules/b')
	assert lock_text.contains('node_modules/c')
}

fn test_cli_capabilities_command() {
	output := os.execute('${cli_test_support.command(false)} capabilities --runtime node')
	assert output.exit_code == 0
	assert output.output.contains('runtime: node')
	assert output.output.contains('yes globalThis')
	assert output.output.contains('yes fs')
	assert output.output.contains('yes path')
}

fn test_cli_ls_command_prints_dependency_tree() {
	base_dir := os.join_path(os.temp_dir(), 'vjsx_cli_ls_test_${os.getpid()}')
	os.rmdir_all(base_dir) or {}
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'a')) or { panic(err) }
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'b')) or { panic(err) }
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'c')) or { panic(err) }
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'devonly')) or { panic(err) }
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'optionalonly')) or { panic(err) }
	os.mkdir_all(os.join_path(base_dir, 'node_modules', 'peeronly')) or { panic(err) }
	os.write_file(os.join_path(base_dir, 'package.json'),
		'{"name":"ls-smoke","version":"1.2.3","dependencies":{"a":"1.0.0","missing":"^9.0.0"},"devDependencies":{"devonly":"4.0.0"},"optionalDependencies":{"optionalonly":"5.0.0"},"peerDependencies":{"peeronly":"6.0.0"}}') or {
		panic(err)
	}
	os.write_file(os.join_path(base_dir, 'package-lock.json'),
		'{"name":"ls-smoke","version":"1.2.3","lockfileVersion":3,"requires":true,"packages":{"":{"name":"ls-smoke","version":"1.2.3","dependencies":{"a":"1.0.0","missing":"^9.0.0"},"devDependencies":{"devonly":"4.0.0"},"optionalDependencies":{"optionalonly":"5.0.0"},"peerDependencies":{"peeronly":"6.0.0"}},"node_modules/a":{"version":"1.0.0","dependencies":{"b":"2.0.0","c":"3.0.0"}},"node_modules/b":{"version":"2.0.0"},"node_modules/c":{"version":"3.0.0"},"node_modules/devonly":{"version":"4.0.0"},"node_modules/optionalonly":{"version":"5.0.0"},"node_modules/peeronly":{"version":"6.0.0"}}}') or {
		panic(err)
	}
	os.write_file(os.join_path(base_dir, 'node_modules', 'a', 'package.json'),
		'{"name":"a","version":"1.0.0"}') or { panic(err) }
	os.write_file(os.join_path(base_dir, 'node_modules', 'b', 'package.json'),
		'{"name":"b","version":"2.0.0"}') or { panic(err) }
	os.write_file(os.join_path(base_dir, 'node_modules', 'c', 'package.json'),
		'{"name":"c","version":"3.0.0"}') or { panic(err) }
	os.write_file(os.join_path(base_dir, 'node_modules', 'devonly', 'package.json'),
		'{"name":"devonly","version":"4.0.0"}') or { panic(err) }
	os.write_file(os.join_path(base_dir, 'node_modules', 'optionalonly', 'package.json'),
		'{"name":"optionalonly","version":"5.0.0"}') or { panic(err) }
	os.write_file(os.join_path(base_dir, 'node_modules', 'peeronly', 'package.json'),
		'{"name":"peeronly","version":"6.0.0"}') or { panic(err) }
	all_output := os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls')
	assert all_output.exit_code == 0
	assert all_output.output.contains('ls-smoke@1.2.3 ')
	assert all_output.output.contains('├─┬ a@1.0.0')
	assert all_output.output.contains('│ ├── b@2.0.0')
	assert all_output.output.contains('│ └── c@3.0.0')
	assert all_output.output.contains('├── devonly@4.0.0')
	assert all_output.output.contains('optionalonly@5.0.0')
	assert all_output.output.contains('peeronly@6.0.0')
	assert all_output.output.contains('UNMET DEPENDENCY missing@^9.0.0')
	depth_output := os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --depth 0')
	assert depth_output.exit_code == 0
	assert !depth_output.output.contains('b@2.0.0')
	assert !depth_output.output.contains('c@3.0.0')
	prod_output :=
		os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --omit=dev --depth 0')
	assert prod_output.exit_code == 0
	assert prod_output.output.contains('a@1.0.0')
	assert !prod_output.output.contains('devonly@4.0.0')
	omit_optional_output :=
		os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --omit=optional --depth 0')
	assert omit_optional_output.exit_code == 0
	assert !omit_optional_output.output.contains('optionalonly@5.0.0')
	omit_peer_output :=
		os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --omit peer --depth 0')
	assert omit_peer_output.exit_code == 0
	assert !omit_peer_output.output.contains('peeronly@6.0.0')
	filter_output := os.execute('cd ${base_dir} && ${cli_test_support.command(false)} list a')
	assert filter_output.exit_code == 0
	assert filter_output.output.contains('└── a@1.0.0')
	assert !filter_output.output.contains('missing@^9.0.0')
	json_output :=
		os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --json --depth 1')
	assert json_output.exit_code == 0
	assert json_output.output.contains('"name": "ls-smoke"')
	assert json_output.output.contains('"version": "1.2.3"')
	assert json_output.output.contains('"a": {')
	assert json_output.output.contains('"b": {')
	assert json_output.output.contains('"devonly": {')
	assert json_output.output.contains('"optionalonly": {')
	assert json_output.output.contains('"peeronly": {')
	assert json_output.output.contains('"dependencyType": "prod"')
	assert json_output.output.contains('"dependencyType": "dev"')
	assert json_output.output.contains('"dependencyType": "optional"')
	assert json_output.output.contains('"dependencyType": "peer"')
	assert !json_output.output.contains('"production"')
	assert json_output.output.contains('"missing": true')
	assert json_output.output.contains('"code": "ELSPROBLEMS"')
	prod_json_output :=
		os.execute('cd ${base_dir} && ${cli_test_support.command(false)} ls --depth=0 --json --omit=dev')
	assert prod_json_output.exit_code == 0
	assert prod_json_output.output.contains('"a": {')
	assert !prod_json_output.output.contains('"devonly": {')
}
