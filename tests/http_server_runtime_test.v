import vjsx
import net.http
import os
import time

fn http_test_read(port int, result chan string) {
	response := http.post('http://127.0.0.1:${port}/echo', 'owned-lane') or {
		result <- 'error'
		return
	}
	result <- response.body
}

fn test_http_server_owner_lane_close_cycles_and_permissions() {
	before := os.ls('/dev/fd') or { []string{} }
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	ready := chan bool{cap: 256}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		session_id:     'http-server-lane'
		async_ready_fn: fn [ready] (_request vjsx.RuntimeHostAsyncReadyRequest) {
			select {
				ready <- true {
				}
				else {
				}
			}
		}
	})
	ctx := session.context()
	value := ctx.js_eval('import http from "node:http"; globalThis.testHttp = http;', 'http-import.mjs', vjsx.type_module) or { panic(err) }
	value.free()
	for _ in 0 .. 20 {
		start := ctx.eval('globalThis.server = testHttp.createServer(async (req,res) => {let text="";for await(const chunk of req)text += new TextDecoder().decode(chunk);res.end(text);});server.listen(0,"127.0.0.1");server.address().port;') or { panic(err) }
		port := start.to_int()
		start.free()
		session.drain_ready_tasks() or { panic(err) }
		result := chan string{cap: 1}
		job := spawn http_test_read(port, result)
		deadline := time.now().unix_milli() + 3000
		mut done := false
		for !done && time.now().unix_milli() < deadline {
			select {
				_ := <-ready {
					session.deliver_wakeup(0) or { panic(err) }
				}
				text := <-result {
					assert text == 'owned-lane'
					done = true
				}
				100 * time.millisecond {
				}
			}
		}
		assert done
		job.wait()
		close := ctx.eval('server.closeAllConnections();server.close();') or { panic(err) }
		close.free()
		for session.websocket_connection_count() > 0 && time.now().unix_milli() < deadline {
			select {
				_ := <-ready {
					session.deliver_wakeup(0) or { panic(err) }
				}
				100 * time.millisecond {
				}
			}
		}
		assert session.websocket_connection_count() == 0
	}
	live := ctx.eval('globalThis.live = testHttp.createServer().listen(0,"127.0.0.1");') or { panic(err) }
	live.free()
	session.drain_ready_tasks() or { panic(err) }
	started := time.now().unix_milli()
	session.close()
	session.close()
	assert time.now().unix_milli() - started < 2000
	after := os.ls('/dev/fd') or { []string{} }
	if before.len > 0 {
		assert after.len <= before.len + 2
	}
}
