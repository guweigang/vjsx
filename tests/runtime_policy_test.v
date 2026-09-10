import os
import runtimejs
import vjsx

fn test_bounded_filesystem_policy_allows_inside_and_rejects_outside() {
	root := os.join_path(os.temp_dir(), 'vjsx_policy_${os.getpid()}')
	outside := os.join_path(os.temp_dir(), 'vjsx_policy_outside_${os.getpid()}.txt')
	os.rmdir_all(root) or {}
	os.rm(outside) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(outside, 'secret') or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
		os.rm(outside) or {}
	}
	policy := vjsx.HostPolicy{
		allow_fs_read: true
		allow_fs_write: true
		fs_read_roots: [root]
		fs_write_roots: [root]
	}
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [root]
		fetch: false
		policy: policy
	})
	defer { session.close() }
	ctx := session.context()
	assert !ctx.has_runtime_module('sqlite')
	value := ctx.eval('
		import fs from "fs";
		fs.writeFileSync("inside.txt", "ok");
		let outsideRead = "allowed";
		let outsideWrite = "allowed";
		try { fs.readFileSync("${outside}"); } catch (err) { outsideRead = String(err.message); }
		try { fs.writeFileSync("${outside}", "bad"); } catch (err) { outsideWrite = String(err.message); }
		globalThis.__policyResult = [fs.readFileSync("inside.txt", "utf8"), outsideRead, outsideWrite].join("|");
	', vjsx.type_module) or { panic(err) }
	value.free()
	ctx.end()
	result := ctx.eval('globalThis.__policyResult') or { panic(err) }
	defer { result.free() }
	parts := result.str().split('|')
	assert parts[0] == 'ok'
	assert parts[1].contains('not found') || parts[1].contains('disabled')
	assert parts[2].contains('not allowed')
	assert os.read_file(outside) or { '' } == 'secret'
}

fn test_network_host_allowlist_and_safe_module_denial() {
	policy := vjsx.HostPolicy{
		allow_network: true
		network_hosts: ['api.example.com', '*.trusted.example']
	}
	assert policy.allows_network_url('https://api.example.com/v1')
	assert policy.allows_network_url('https://edge.trusted.example/data')
	assert !policy.allows_network_url('https://example.com/')
	assert !vjsx.host_policy_safe().allows_network_url('https://api.example.com/')
	mut network_session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		policy: policy
	})
	defer { network_session.close() }
	network_ctx := network_session.context()
	assert !network_ctx.has_runtime_module('mysql')
	value := network_ctx.eval('
		import http from "http";
		http.get("http://denied.example/path", () => {}).on("error", err => {
			globalThis.__networkDenied = String(err.message);
		});
	', vjsx.type_module) or { panic(err) }
	value.free()
	network_ctx.end()
	denied := network_ctx.eval('globalThis.__networkDenied') or { panic(err) }
	assert denied.str().contains('network host is not allowed')
	denied.free()

	mut extension := runtimejs.new_node_extension_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		policy: vjsx.host_policy_safe()
	}, vjsx.HostApiConfig{}, fn (_ctx &vjsx.Context) vjsx.Value {
		return _ctx.js_undefined()
	})
	defer { extension.close() }
	ctx := extension.context()
	assert !ctx.has_runtime_module('fetch')
	assert !ctx.has_runtime_module('http')
	assert !ctx.has_runtime_module('https')
	assert !ctx.has_runtime_module('child_process')
	assert !ctx.has_runtime_module('sqlite')
	assert !ctx.has_runtime_module('mysql')
}
