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
