import os
import time
import vjsx

fn main() {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	ctx.install_node_compat(vjsx.NodeCompatConfig{ websocket: false })
	session.try_install_websocket(vjsx.WebSocketConfig{ connect_timeout_ms: 200, io_timeout_ms: 200 }) or { panic(err) }
	global := ctx.js_global()
	global.set('fixtureUrl', os.args[1])
	global.free()
	started := time.now().unix_milli()
	result := ctx.eval('
  globalThis.timeoutError = "";
  const socket = new WebSocket(fixtureUrl);
  socket.onerror = e => globalThis.timeoutError = e.message;
 ') or { panic(err) }
	result.free()
	session.pump_until_idle()
	reason := ctx.js_global('timeoutError')
	assert reason.str().contains('timed out')
	reason.free()
	assert time.now().unix_milli() - started < 1500
	assert session.websocket_connection_count() == 0
	println('PASS real TLS/upgrade timeout')
}
