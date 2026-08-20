import vjsx

fn install_fake_fetch_runtime(ctx &vjsx.Context) {
	ctx.install_event_globals()
	ctx.install_abort_globals()
	ctx.install_timer_globals()
	ctx.install_url_globals()
	ctx.install_encoding_globals()
	ctx.eval('
		globalThis.__bootstrap = {
			util: {
				isArrayBuffer: (value) => value instanceof ArrayBuffer,
				isTypedArray: (value) => ArrayBuffer.isView(value) && !(value instanceof DataView),
				isRedirect: (status) => [301, 302, 303, 307, 308].includes(status),
			},
			core_fetch(url, init, resolve, reject) {
				globalThis.__fetch_abort_core_calls = (globalThis.__fetch_abort_core_calls || 0) + 1;
				const timer = setTimeout(() => {
					resolve({
						status: 200,
						status_message: "OK",
						header: { "x-test": "yes" },
						body: new TextEncoder().encode(url.endsWith("/ok") ? "ok" : "late").buffer,
					});
				}, 25);
				return () => {
					clearTimeout(timer);
					reject(new DOMException("This operation was aborted", "AbortError"));
				};
			},
		};
	') or {
		panic(err)
	}
	ctx.eval_runtime_file('web/js/fetch.js', vjsx.type_module) or { panic(err) }
}

fn test_fetch_rejects_pre_aborted_signal() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	install_fake_fetch_runtime(ctx)
	value := ctx.eval('fetch("https://example.test/pre", {
		signal: AbortSignal.abort()
	}).then(
		() => "resolved",
		(err) => err.name + ":" + err.message
	)') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'AbortError:This operation was aborted'
}

fn test_fetch_rejects_when_signal_aborts_before_core_fetch_resolves() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	install_fake_fetch_runtime(ctx)
	value := ctx.eval('
		(async () => {
			const controller = new AbortController();
			const pending = fetch("https://example.test/late", {
				signal: controller.signal
			}).then(
				() => "resolved",
				(err) => err.name + ":" + err.message
			);
			setTimeout(() => controller.abort(), 1);
			const aborted = await pending;
			await new Promise((resolve) => setTimeout(resolve, 50));
			const okResponse = await fetch("https://example.test/ok");
			const okText = await okResponse.text();
			return [
				aborted,
				okText,
				String(globalThis.__fetch_abort_core_calls),
			].join("|");
		})()
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'AbortError:This operation was aborted|ok|2'
}
