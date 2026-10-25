import net.http
import os
import time
import vjsx

fn host_http_payload() []u8 {
	return [u8(0), 1, 2, 255, 10, 13, 65]
}

struct HostHttpHandler {}

fn (mut handler HostHttpHandler) handle(req http.Request) http.Response {
	match req.url.all_before('?') {
		'/redirect' {
			mut response := http.Response{
				header: http.new_header(key: .location, value: '/payload')
			}
			response.status_code = 302
			response.status_msg = 'Found'
			response.set_version(req.version)
			return response
		}
		'/payload' {
			mut response := http.Response{
				body: host_http_payload().bytestr()
			}
			response.set_status(.ok)
			response.set_version(req.version)
			return response
		}
		else {
			mut response := http.Response{}
			response.set_status(.not_found)
			response.set_version(req.version)
			return response
		}
	}
}

fn test_host_http_runtime_download_and_pipe() {
	mut server := &http.Server{
		accept_timeout:       200 * time.millisecond
		addr:                 '127.0.0.1:18197'
		handler:              HostHttpHandler{}
		show_startup_message: false
	}
	server_thread := spawn server.listen_and_serve()
	server.wait_till_running() or { panic(err) }
	defer {
		server.stop()
		server_thread.wait()
	}

	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots:     [@VMODROOT]
		process_args: ['host_http_runtime.mjs', 'http://127.0.0.1:18197']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	assert ctx.has_runtime_module('node:http')
	assert ctx.has_runtime_module('node:https')
	assert vjsx.runtime_profile_snapshot(ctx).has_capability('node:http')
	assert vjsx.runtime_profile_snapshot(ctx).has_capability('node:https')
	value := ctx.run_file('./tests/host_http_runtime.mjs', vjsx.type_module) or { panic(err) }
	value.free()

	result := ctx.js_global('__host_http_result')
	target := ctx.js_global('__host_http_target')
	defer {
		result.free()
		target.free()
	}
	assert result.to_string() == 'function\nfunction\n302\n/payload\n200'
	target_path := target.to_string()
	assert os.read_bytes(target_path) or { panic(err) } == host_http_payload()
	os.rmdir_all(os.dir(target_path)) or {}
}

fn test_host_http_aliases_respect_network_policy() {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	ctx.install_http_module_policy(vjsx.host_policy_safe())
	value := ctx.js_eval('
		import http from "http";
		import nodeHttp, { get } from "node:http";
		globalThis.__denied = false;
		if (http !== nodeHttp || http.get !== get) throw new Error("alias mismatch");
		get("http://127.0.0.1:1").on("error", error => {
			globalThis.__denied = error.message.includes("network");
		});
	', 'http-policy.mjs', vjsx.type_module) or { panic(err) }
	value.free()
	denied := ctx.js_global('__denied')
	defer { denied.free() }
	assert denied.to_bool()
}
