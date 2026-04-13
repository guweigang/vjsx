import net
import net.http
import time
import vjsx

struct HostFetchHandler {}

fn (mut handler HostFetchHandler) handle(req http.Request) http.Response {
	match req.url.all_before('?') {
		'/echo' {
			mut header := http.new_header()
			header.add_custom('x-echo-method', req.method.str()) or {}
			header.add_custom('x-echo-query', req.url.all_after('?')) or {}
			header.add_custom('x-echo-client', req.header.custom_values('X-Client').join(', ')) or {}
			mut response := http.Response{
				body:   req.data
				header: header
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

fn test_node_runtime_fetch_globals() {
	listener := net.listen_tcp(.ip, 'localhost:0') or { panic(err) }
	port := listener.addr() or { panic(err) }.port() or { panic(err) }
	mut server := &http.Server{
		accept_timeout:       200 * time.millisecond
		addr:                 '127.0.0.1:${port}'
		handler:              HostFetchHandler{}
		listener:             listener
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
		process_args: ['host_fetch_runtime.mjs', 'http://127.0.0.1:${port}']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.run_file('./tests/host_fetch_runtime.mjs', vjsx.type_module) or { panic(err) }
	value.free()

	result := ctx.js_global('__host_fetch_result')
	defer {
		result.free()
	}
	assert result.to_string() == 'function\nfunction\nfunction\nfunction\n200\ntrue\nPOST\nvia=request\nvjsx\nping\napplication/json\n{"ok":true}'
}
