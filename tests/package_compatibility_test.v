import os
import runtimejs
import vjsx

fn package_compat_test_root(name string) string {
	return os.join_path(os.temp_dir(), 'vjsx_package_compat_${name}_${os.getpid()}')
}

fn test_package_compatibility_checks_only_reachable_module_graph() {
	root := package_compat_test_root('reachable')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'package.json'),
		'{"name":"reachable-native","version":"1.0.0","type":"module","exports":"./index.js"}') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'index.js'),
		'import { value } from "./value.js"; globalThis.__package_compat_executed = true; throw new Error("must not execute"); export { value };') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'value.js'), 'export const value = 42;') or { panic(err) }
	os.write_file(os.join_path(root, 'binding.gyp'), '{}') or { panic(err) }
	os.write_file_array(os.join_path(root, 'unused.node'), [u8(0), 1, 2, 3]) or { panic(err) }

	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [root]
	})
	defer {
		session.close()
	}
	ctx := session.context()
	entry := runtimejs.check_runtime_package_entry(ctx, root, os.join_path(root, '.check')) or {
		panic(err)
	}
	assert entry == os.real_path(os.join_path(root, 'index.js'))
	executed := ctx.eval('globalThis.__package_compat_executed === true') or { panic(err) }
	defer {
		executed.free()
	}
	assert !executed.to_bool()
}

fn test_package_compatibility_rejects_reachable_unsupported_host_module() {
	root := package_compat_test_root('unsupported')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'package.json'),
		'{"name":"unsupported-host","version":"1.0.0","type":"module","exports":"./index.js"}') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'index.js'),
		'import { Worker } from "node:worker_threads"; export { Worker };') or { panic(err) }

	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [root]
	})
	defer {
		session.close()
	}
	ctx := session.context()
	runtimejs.check_runtime_package_entry(ctx, root, os.join_path(root, '.check')) or {
		assert err.msg().contains('worker_threads') || err.msg().contains('could not load module')
		return
	}
	assert false
}
