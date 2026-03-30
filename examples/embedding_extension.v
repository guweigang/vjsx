import os
import runtimejs
import vjsx

fn demo_host_api() vjsx.HostValueBuilder {
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

fn demo_host_config() vjsx.HostApiConfig {
	return vjsx.HostApiConfig{
		globals: [
			vjsx.HostGlobalBinding{
				name:  'appName'
				value: vjsx.host_value('demo-host')
			},
		]
		modules: [
			vjsx.HostModuleBinding{
				name:    'host-tools'
				install: vjsx.host_module_object(vjsx.HostObjectField{
					name:  'version'
					value: vjsx.host_value('v1')
				})
			},
		]
	}
}

fn main() {
	script_path := os.join_path(@VMODROOT, 'examples', 'js', 'host_extension.mjs')
	mut extension_session := runtimejs.new_node_extension_session(vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
		process_args: ['host_extension.mjs']
	}, demo_host_config(), demo_host_api())
	defer {
		extension_session.close()
	}

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

	greet := extension.call_export('greet', 'world') or { panic(err) }
	defer {
		greet.free()
	}
	println('greet => ${greet.to_string()}')

	status := extension.call_default_method('status', 'ready') or { panic(err) }
	defer {
		status.free()
	}
	println('status => ${status.to_string()}')

	dispose := extension.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	println('dispose => ${dispose.to_string()}')
}
