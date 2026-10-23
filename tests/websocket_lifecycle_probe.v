// Run against tests/websocket_network.py's real loopback fixture.
import os
import time
import vjsx

fn main() {
	before_fds := os.ls('/dev/fd') or { []string{} }
	mut session := vjsx.new_runtime_session()
	ctx := session.context()
	ctx.install_node_compat(vjsx.NodeCompatConfig{ websocket: false })
	session.try_install_websocket(vjsx.WebSocketConfig{
		queue_capacity:    4
		max_message_bytes: 64
		max_queued_bytes:  128
		io_timeout_ms:     1000
		ca_file:           if os.args.len > 2 { os.args[2] } else { '' }
	}) or { panic(err) }
	global := ctx.js_global()
	global.set('fixtureUrl', os.args[1])
	global.free()
	code := ctx.eval('
  globalThis.finished = 0;
  function cycle() {
   const socket = new WebSocket(fixtureUrl);
   socket.onopen = () => socket.close(3000, "cycle");
   socket.onclose = e => {
    if (!e.wasClean) throw Error("unclean cycle");
    if (++finished < 128) cycle();
   };
  }
  cycle();
 ') or { panic(err) }
	code.free()
	session.pump_until_idle()
	result := ctx.js_global('finished')
	assert result.to_int() == 128
	result.free()
	assert session.websocket_connection_count() == 0
	assert !session.needs_wakeup()

	// Hold the owner lane while the real peer sends a burst. The producer must
	// terminate at the bounded queue, with exactly one terminal delivery.
	burst := ctx.eval('globalThis.overflowClosed = 0; globalThis.overflowErrors = 0; const burst = new WebSocket(fixtureUrl + "/burst"); burst.onerror = () => overflowErrors++; burst.onclose = () => overflowClosed++;') or { panic(err) }
	burst.free()
	time.sleep(200 * time.millisecond)
	session.pump_until_idle()
	closed := ctx.js_global('overflowClosed')
	errors := ctx.js_global('overflowErrors')
	assert closed.to_int() == 1 && errors.to_int() == 1
	closed.free()
	errors.free()
	assert session.websocket_connection_count() == 0
	oversized := ctx.eval('globalThis.quota = false; const send = new WebSocket(fixtureUrl); send.onopen = () => { try { send.send("x".repeat(65)); } catch(e) { quota = e.name === "QuotaExceededError"; } };') or { panic(err) }
	oversized.free()
	session.pump_until_idle()
	quota := ctx.js_global('quota')
	assert quota.to_bool()
	quota.free()
	assert session.websocket_connection_count() == 0

	// Exercise the embedder scheduler path separately from QuickJS's stdlib loop.
	ready := chan bool{cap: 32}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		session_id:     'websocket-lane'
		async_ready_fn: fn [ready] (_request vjsx.RuntimeHostAsyncReadyRequest) {
			select {
				ready <- true {
				}
				else {
				}
			}
		}
	})
	session.request_wakeup_at(session.now_ms() + 10000, 'older-generation')
	stale_generation := session.wakeup_generation()
	session.request_wakeup_at(session.now_ms() + 9000, 'newer-generation')
	current_generation := session.wakeup_generation()
	scheduled := ctx.eval('globalThis.ownerDelivered = 0; const scheduled = new WebSocket(fixtureUrl); scheduled.onopen = () => { ownerDelivered++; scheduled.close(); };') or { panic(err) }
	scheduled.free()
	select {
		_ := <-ready {
		}
		2000 * time.millisecond {
			panic('no native stream wakeup')
		}
	}
	assert session.deliver_wakeup(stale_generation) or { panic(err) } == 0
	before_delivery := ctx.js_global('ownerDelivered')
	assert before_delivery.to_int() == 0
	before_delivery.free()
	session.deliver_wakeup(current_generation) or { panic(err) }
	for session.websocket_connection_count() > 0 {
		select {
			_ := <-ready {
				session.deliver_wakeup(0) or { panic(err) }
			}
			2000 * time.millisecond {
				panic('no native stream close wakeup')
			}
		}
	}
	delivered := ctx.js_global('ownerDelivered')
	assert delivered.to_int() == 1
	delivered.free()
	// A live connection must be cancelled and joined before the Context is freed.
	start := ctx.eval('globalThis.old = new WebSocket(fixtureUrl);') or { panic(err) }
	start.free()
	assert session.websocket_connection_count() == 1
	closed_at := time.now().unix_milli()
	session.close()
	session.close()
	assert time.now().unix_milli() - closed_at < 3000
	assert session.websocket_connection_count() == 0
	after_fds := os.ls('/dev/fd') or { []string{} }
	if before_fds.len > 0 {
		assert after_fds.len <= before_fds.len + 2
	}
	println('PASS 128 same-session cycles, bounded queues, shutdown and fd recovery')
}
