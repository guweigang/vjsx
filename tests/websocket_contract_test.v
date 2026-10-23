import vjsx
import web

fn test_websocket_constructor_and_bounds() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer { session.close() }
	value := session.context().eval('
  (() => {
   if (typeof WebSocket !== "function") throw Error("missing WebSocket");
   for (const [url, protocols] of [["ftp://localhost", []], ["ws://localhost/#a", []], ["ws://localhost", ["x", "x"]]]) {
    let failed = false;
    try { new WebSocket(url, protocols); } catch(e) { failed = true; }
    if (!failed) throw Error("invalid constructor accepted");
   }
   return WebSocket.OPEN === 1 && WebSocket.prototype.CLOSED === 3;
  })()
 ') or { panic(err) }
	assert value.to_bool()
	value.free()
}

fn test_browser_profile_websocket_survives_bootstrap_cleanup() {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	web.inject_browser_runtime(ctx)
	socket := ctx.js_global('WebSocket')
	assert socket.is_function()
	// Bootstrap cleanup is usable without a BrowserHostConfig; it must neither
	// reinstall nor remove the already installed WebSocket constructor.
	global := ctx.js_global()
	bootstrap := ctx.js_object()
	global.set('__bootstrap', bootstrap)
	bootstrap.free()
	assert web.delete_bootstrap(ctx)
	assert !web.delete_bootstrap(ctx)
	after := ctx.js_global('WebSocket')
	assert socket.strict_eq(after)
	after.free()
	socket.free()
	global.free()
}
