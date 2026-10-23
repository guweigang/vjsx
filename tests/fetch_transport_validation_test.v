import net
import net.http
import os
import time
import vjsx

struct FetchTransportValidationHandler {}

fn (mut handler FetchTransportValidationHandler) handle(_req http.Request) http.Response {
	if _req.url != '/fast' && _req.url != '/echo' { time.sleep(300 * time.millisecond) }
	return http.Response{ body: if _req.url == '/echo' { _req.data } else { 'ok' } }
}

// Both transports must allow JS timers and overlapping network requests.
fn test_fetch_transport_timer_progress_and_parallel_requests() {
	listener := net.listen_tcp(.ip, '127.0.0.1:0') or { panic(err) }
	port := listener.addr() or { panic(err) }.port() or { panic(err) }
	mut server := &http.Server{
		// Cancelled/timed-out clients leave slow handlers running. Keep enough
		// server capacity for recovery requests even when VJOBS is only 1 or 2.
		worker_num:           4
		accept_timeout:       100 * time.millisecond
		addr:                 '127.0.0.1:${port}'
		handler:              FetchTransportValidationHandler{}
		listener:             listener
		show_startup_message: false
	}
	worker := spawn server.listen_and_serve()
	server.wait_till_running() or { panic(err) }
	defer {
		server.stop()
		worker.wait()
	}
	for use_curl in [true, false] {
		curl_path := os.find_abs_path_of_executable('curl') or { '' }
		if use_curl && curl_path == '' { continue }
		mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
			fetch_config: vjsx.FetchGlobalsConfig{
				curl_proxy_fallback: use_curl
				curl_path:           if use_curl { curl_path } else { '' }
				read_timeout:        2 * time.second
				write_timeout:       2 * time.second
				max_retries:         0
			}
		})
		ctx := session.context()
		value := ctx.eval('
			(async () => {
				let ticked = false;
				const timer = setTimeout(() => { ticked = true; }, 20);
				// A long wrapper cancellation deadline must not delay ready
				// Promise continuations after the network response arrives.
				const watchdog = setTimeout(() => {}, 2000);
				const started = Date.now();
				const responses = await Promise.all([
					fetch("http://127.0.0.1:${port}/one"),
					fetch("http://127.0.0.1:${port}/two"),
				]);
				const progressed = ticked;
				clearTimeout(timer);
				const bodies = await Promise.all(responses.map(r => r.text()));
				clearTimeout(watchdog);
				return [progressed, Date.now() - started, ...bodies].join("|");
			})()
		') or { panic(err) }
		resolved := session.resolve_value(value) or { panic(err) }
		result := resolved.to_string()
		println('fetch transport=${if use_curl { 'curl' } else { 'native' }} timer|elapsed_ms|bodies=${result}')
		parts := result.split('|')
		assert parts[0] == 'true'
		assert parts[2..] == ['ok', 'ok']
		assert parts[1].int() < 550
		resolved.free()
		value.free()
		session.close()
	}
	// Native deadlines, cancellation, binary payloads, and recovery share the
	// managed session completion queue, including late worker completions.
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{
			timeout_ms:              80
			max_concurrent_requests: 4
			read_timeout:            time.second
			write_timeout:           time.second
		}
	})
	ctx := session.context()
	value := ctx.eval('
		(async () => {
			const controller = new AbortController();
			const events = [];
			const started = Date.now();
			let abortElapsed = 0;
			const aborted = fetch("http://127.0.0.1:${port}/abort", {signal: controller.signal})
				.then(() => events.push("unexpected"), e => { abortElapsed = Date.now() - started; events.push(e.name); });
			setTimeout(() => controller.abort(), 20);
			const timed = fetch("http://127.0.0.1:${port}/timeout")
				.then(() => events.push("unexpected"), e => events.push(e.name));
			await Promise.all([aborted, timed]);
			if (abortElapsed > 150 || Date.now() - started > 220) throw Error("cancellation/deadline did not settle promptly");
			const binary = new Uint8Array([0, 255, 1, 128]);
			const echo = await fetch("http://127.0.0.1:${port}/echo", {method: "POST", body: binary});
			const bytes = Array.from(new Uint8Array(await echo.arrayBuffer())).join(",");
			const form = new FormData();
			form.append("name", "vjsx");
			const formResponse = await fetch("http://127.0.0.1:${port}/echo", {method: "POST", body: form});
			const formText = await formResponse.text();
			if (!formText.includes("name=\\"name\\"") || !formText.includes("vjsx")) throw Error("multipart mismatch");
			await new Promise(r => setTimeout(r, 350));
			const fast = await fetch("http://127.0.0.1:${port}/fast");
			const fastText = await fast.text();
			const late = fetch("http://127.0.0.1:${port}/busy")
				.then(() => "unexpected", e => e.name);
			const until = Date.now() + 400;
			while (Date.now() < until) {}
			const busyTimeout = await late;
			const preAborted = await fetch("http://127.0.0.1:${port}/fast", {signal: AbortSignal.abort()})
				.then(() => "unexpected", e => e.name);
			return [events.join(","), bytes, fastText, busyTimeout, preAborted].join("|");
		})()
	') or { panic(err) }
	resolved := session.resolve_value(value) or { panic(err) }
	assert resolved.to_string() == 'AbortError,TimeoutError|0,255,1,128|ok|TimeoutError|AbortError'
	assert session.pending_host_async_operation_count() == 0
	assert session.pending_host_async_event_count() == 0
	resolved.free()
	value.free()
	session.close()
	mut bounded := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{ max_concurrent_requests: 1 }
	})
	bounded_value := bounded.context().eval('
		(async () => {
			const controller = new AbortController();
			const pending = fetch("http://127.0.0.1:${port}/bounded", {signal: controller.signal}).catch(e => e.name);
			const blocked = await fetch("http://127.0.0.1:${port}/fast").then(() => "unexpected", e => e.message);
			controller.abort();
			const cancelled = await pending;
			// A cancelled JS Promise must not free the still-running worker slot.
			const stillBlocked = await fetch("http://127.0.0.1:${port}/fast").then(() => "unexpected", e => e.message);
			await new Promise(r => setTimeout(r, 350));
			const fast = await fetch("http://127.0.0.1:${port}/fast");
			return [blocked, cancelled, stillBlocked, await fast.text()].join("|");
		})()
	') or { panic(err) }
	bounded_result := bounded.resolve_value(bounded_value) or { panic(err) }
	assert bounded_result.to_string() == 'native fetch concurrency limit reached|AbortError|native fetch concurrency limit reached|ok'
	assert bounded.pending_host_async_operation_count() == 0
	bounded_result.free()
	bounded_value.free()
	bounded.close()
	// Closing while I/O is in flight must invalidate worker completion ports
	// without letting worker threads touch a freed QuickJS context.
	mut closing := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	pending := closing.context().eval('fetch("http://127.0.0.1:${port}/close").catch(() => {})') or { panic(err) }
	pending.free()
	assert closing.pending_host_async_operation_count() == 1
	closing.close()
	time.sleep(350 * time.millisecond)
	assert closing.pending_host_async_operation_count() == 0
	assert closing.pending_host_async_event_count() == 0
}
