import os
import runtimejs
import vjsx

fn manifest_demo_host_api() vjsx.HostValueBuilder {
	return vjsx.host_object(vjsx.HostObjectField{
		name:  'app'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'name'
			value: vjsx.host_value('demo-host')
		})
	}, vjsx.HostObjectField{
		name:  'logger'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'prefix'
			value: vjsx.host_value('log')
		})
	})
}

fn manifest_demo_host_config() vjsx.HostApiConfig {
	return vjsx.HostApiConfig{
		modules: [
			vjsx.HostModuleBinding{
				name:    'host-tools'
				install: vjsx.host_module_object(vjsx.HostObjectField{
					name:  'version'
					value: vjsx.host_value('v2')
				}, vjsx.HostObjectField{
					name:  'greet'
					value: fn (ctx &vjsx.Context) vjsx.Value {
						return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
							return ctx.js_string('host-tools:' + args[0].to_string())
						})
					}
				})
			},
		]
	}
}

fn main() {
	script_path := os.join_path(@VMODROOT, 'examples', 'js', 'host_extension_manifest.mjs')
	mut extension_session := runtimejs.new_node_extension_session(vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
		process_args: ['host_extension_manifest.mjs']
	}, manifest_demo_host_config(), manifest_demo_host_api())
	defer {
		extension_session.close()
	}

	manifest := extension_session.describe_extension(script_path) or { panic(err) }
	println('extension => ${manifest.name}')
	println('hooks => ${manifest.activate_export}/${manifest.handle_export}/${manifest.dispose_export}')

	mut extension := extension_session.load_extension(script_path, vjsx.ScriptPluginHooks{}) or {
		panic(err)
	}
	defer {
		extension.close()
	}

	activate := extension.activate('boot') or { panic(err) }
	defer {
		activate.free()
	}
	println('activate => ${activate.to_string()}')

	handle := extension.handle('task-1') or { panic(err) }
	defer {
		handle.free()
	}
	println('handle => ${handle.to_string()}')

	service := extension.call_service('hostGreeting', 'world') or { panic(err) }
	defer {
		service.free()
	}
	println('service => ${service.to_string()}')

	dispose := extension.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	println('dispose => ${dispose.to_string()}')
}
