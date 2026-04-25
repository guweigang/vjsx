import vjsx

fn test_cli_runner() {
	assert true
}

fn test_install_host_compat() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_host(
		console: false
		fs:      false
		path:    false
		process: false
	)
	assert true
}

fn test_install_runtime_globals_profile() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(
		binary: true
		timer:  false
		url:    true
	)
	value := ctx.eval('typeof atob + "|" + typeof Buffer + "|" + typeof URL + "|" + typeof setTimeout') or {
		panic(err)
	}
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'function|object|function|undefined'
}

fn test_runtime_globals_presets() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(vjsx.runtime_globals_minimal())
	value := ctx.eval('typeof atob + "|" + typeof URL + "|" + typeof setTimeout') or { panic(err) }
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'function|function|undefined'
}

fn test_runtime_profile_snapshot_for_runtime_globals_minimal() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(vjsx.runtime_globals_minimal())
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	assert snapshot.has_abort_controller
	assert snapshot.has_abort_signal
	assert snapshot.has_event_target
	assert snapshot.has_url
	assert snapshot.has_buffer
	assert snapshot.has_set_timeout == false
	assert snapshot.has_node_timers_promises == false
	assert snapshot.has_process == false
	assert snapshot.has_fs_module == false
	assert ctx.runtime_modules().len == 0
	assert snapshot.matches(.runtime_minimal)
	assert snapshot.infer_kind() == .runtime_minimal
	assert snapshot.missing_for(.node) == [
		'process',
		'setTimeout',
		'clearTimeout',
		'node:timers/promises',
		'fs',
		'path',
		'http',
		'https',
	]
}

fn test_runtime_globals_install_event_and_abort_controller() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(vjsx.runtime_globals_minimal())
	ctx.eval('
		const events = [];
		const controller = new AbortController();
		controller.signal.addEventListener("abort", () => {
			events.push("listener:" + controller.signal.reason);
		});
		controller.signal.onabort = () => {
			events.push("onabort:" + controller.signal.reason);
		};
		const before = controller.signal.aborted;
		controller.abort("bye");
		controller.abort("ignored");
		let threw = false;
		try {
			controller.signal.throwIfAborted();
		} catch (err) {
			threw = err === "bye";
		}
		const aborted = AbortSignal.abort("x");
		const first = new AbortController();
		const second = new AbortController();
		const combined = AbortSignal.any([first.signal, second.signal]);
		second.abort("second");
		let timeoutRequiresTimer = false;
		try {
			AbortSignal.timeout(1);
		} catch (err) {
			timeoutRequiresTimer = err instanceof TypeError;
		}
		globalThis.__abort_test = [
			typeof EventTarget,
			typeof AbortController,
			typeof AbortSignal,
			String(before),
			String(controller.signal.aborted),
			String(controller.signal.reason),
			events.join(","),
			String(threw),
			String(aborted.aborted),
			String(aborted.reason),
			String(combined.aborted),
			String(combined.reason),
			String(timeoutRequiresTimer)
		].join("|");
	') or {
		panic(err)
	}
	value := ctx.eval('globalThis.__abort_test') or { panic(err) }
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'function|function|function|false|true|bye|listener:bye,onabort:bye|true|true|x|true|second|true'
}

fn test_node_compat_minimal_preset() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_node_compat(vjsx.node_compat_minimal([], ['inline.js']))
	value := ctx.eval('typeof console + "|" + typeof process + "|" + typeof Buffer + "|" + typeof setTimeout + "|" + process.argv.length') or {
		panic(err)
	}
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'object|object|object|undefined|1'
}

fn test_runtime_profile_snapshot_for_node_compat_minimal() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_node_compat(vjsx.node_compat_minimal([], ['inline.js']))
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	assert snapshot.has_abort_controller
	assert snapshot.has_event_target
	assert snapshot.has_buffer
	assert snapshot.has_process
	assert snapshot.has_set_timeout == false
	assert snapshot.has_node_timers_promises
	assert snapshot.has_fs_module == false
	assert snapshot.has_http_module == false
	assert snapshot.has_fetch == false
	assert 'node:timers/promises' in ctx.runtime_modules()
	assert 'path' in ctx.runtime_modules()
	assert 'fs' !in ctx.runtime_modules()
	assert snapshot.matches(.node_minimal)
	assert snapshot.infer_kind() == .node_minimal
	assert snapshot.has_path_module
	assert snapshot.missing_for(.node) == ['setTimeout', 'clearTimeout', 'fs', 'http', 'https']
}

fn test_install_script_runtime_profile() {
	mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
		process_args: ['inline.js', 'arg-one']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('typeof console + "|" + typeof process + "|" + typeof Buffer + "|" + typeof setTimeout + "|" + process.argv.join(",") + "|" + typeof atob') or {
		panic(err)
	}
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'object|object|object|undefined|inline.js,arg-one|function'
}

fn test_runtime_profile_snapshot_for_script_runtime() {
	mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	snapshot := vjsx.runtime_profile_snapshot(session.context())
	assert snapshot.has_abort_controller
	assert snapshot.has_event_target
	assert snapshot.has_buffer
	assert snapshot.has_process
	assert snapshot.has_set_timeout == false
	assert snapshot.has_node_timers_promises
	assert snapshot.has_path_module
	assert snapshot.has_fs_module == false
	assert snapshot.has_http_module == false
	assert snapshot.matches(.script)
	assert snapshot.infer_kind() == .script
	assert snapshot.missing_for(.script).len == 0
}

fn test_install_node_runtime_profile() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('typeof console + "|" + typeof process + "|" + typeof Buffer + "|" + typeof setTimeout') or {
		panic(err)
	}
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'object|object|object|function'
}

fn test_runtime_profile_snapshot_for_node_runtime() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	snapshot := vjsx.runtime_profile_snapshot(session.context())
	assert snapshot.has_abort_controller
	assert snapshot.has_event_target
	assert snapshot.has_buffer
	assert snapshot.has_process
	assert snapshot.has_set_timeout
	assert snapshot.has_clear_timeout
	assert snapshot.has_node_timers_promises
	assert snapshot.has_fs_module
	assert snapshot.has_path_module
	assert snapshot.has_http_module
	assert snapshot.has_https_module
	assert snapshot.matches(.node)
	assert snapshot.infer_kind() == .node
	assert snapshot.missing_for(.node).len == 0
}

fn test_node_timers_promises_supports_abort_signal() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.eval('
		import { setTimeout as delay } from "node:timers/promises";
		const controller = new AbortController();
		globalThis.__node_timer_abort_result = delay(50, "done", {
			signal: controller.signal
		}).then(
			() => "resolved",
			(err) => err.name + ":" + err.cause
		);
		controller.abort("stop");
	',
		vjsx.type_module) or { panic(err) }
	promise_value := ctx.js_global('__node_timer_abort_result')
	defer {
		promise_value.free()
	}
	resolved := session.resolve_value(promise_value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'AbortError:stop'
}

fn test_node_timers_promises_resolves_value() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.eval('
		import * as timers from "node:timers/promises";
		globalThis.__node_timer_value = timers.setTimeout(0, "ok");
	',
		vjsx.type_module) or { panic(err) }
	promise_value := ctx.js_global('__node_timer_value')
	defer {
		promise_value.free()
	}
	resolved := session.resolve_value(promise_value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'ok'
}

fn test_install_host_api_registers_globals_and_modules() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(vjsx.runtime_globals_minimal())
	ctx.install_host_api(
		globals: [
			vjsx.HostGlobalBinding{
				name:  'appName'
				value: vjsx.host_value('embedder')
			},
			vjsx.HostGlobalBinding{
				name:  'hostMultiply'
				value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
					return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
						if args.len < 2 {
							return ctx.js_int(0)
						}
						return ctx.js_int(args[0].to_int() * args[1].to_int())
					})
				}
			},
		]
		modules: [
			vjsx.HostModuleBinding{
				name:    'host-tools'
				install: vjsx.host_module_exports(vjsx.HostModuleExport{
					name:  'answer'
					value: vjsx.host_value(42)
				}, vjsx.HostModuleExport{
					name:  'describe'
					value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
						return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
							if args.len == 0 {
								return ctx.js_string('host:')
							}
							return ctx.js_string('host:' + args[0].str())
						})
					}
				})
			},
		]
	)
	ctx.eval('
		import hostTools, { answer, describe } from "host-tools";
		globalThis.__host_api_result = [
			globalThis.appName,
			String(globalThis.hostMultiply(6, 7)),
			String(answer),
			describe("ok"),
			String(hostTools.answer),
			hostTools.describe("default")
		].join("|");
	',
		vjsx.type_module) or { panic(err) }
	value := ctx.eval('globalThis.__host_api_result') or { panic(err) }
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'embedder|42|42|host:ok|42|host:default'
}

fn test_install_host_api_registers_host_objects() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_runtime_globals(vjsx.runtime_globals_minimal())
	ctx.install_host_api(
		globals: [
			vjsx.HostGlobalBinding{
				name:  'host'
				value: vjsx.host_object(vjsx.HostObjectField{
					name:  'name'
					value: vjsx.host_value('embedder')
				}, vjsx.HostObjectField{
					name:  'math'
					value: vjsx.host_object(vjsx.HostObjectField{
						name:  'add'
						value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
							return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
								return ctx.js_int(args[0].to_int() + args[1].to_int())
							})
						}
					})
				})
			},
		]
		modules: [
			vjsx.HostModuleBinding{
				name:    'host-service'
				install: vjsx.host_module_object(vjsx.HostObjectField{
					name:  'version'
					value: vjsx.host_value('v1')
				}, vjsx.HostObjectField{
					name:  'greet'
					value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
						return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
							return ctx.js_string('hello:' + args[0].str())
						})
					}
				}, vjsx.HostObjectField{
					name:  'nested'
					value: vjsx.host_object(vjsx.HostObjectField{
						name:  'flag'
						value: vjsx.host_value(true)
					})
				})
			},
		]
	)
	ctx.eval('
		import hostService, { version, greet } from "host-service";
		globalThis.__host_object_result = [
			host.name,
			String(host.math.add(2, 5)),
			version,
			greet("module"),
			String(hostService.version),
			hostService.greet("default"),
			String(hostService.nested.flag)
		].join("|");
	',
		vjsx.type_module) or { panic(err) }
	value := ctx.eval('globalThis.__host_object_result') or { panic(err) }
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'embedder|7|v1|hello:module|v1|hello:default|true'
}
