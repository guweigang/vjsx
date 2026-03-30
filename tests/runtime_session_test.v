import os
import vjsx
import runtimejs

fn test_runtime_session_close_is_idempotent() {
	mut session := vjsx.new_runtime_session()
	ctx := session.context()
	value := ctx.eval('1 + 1') or { panic(err) }
	ctx.end()
	assert value.to_int() == 2
	value.free()
	assert session.is_closed() == false
	session.close()
	assert session.is_closed() == true
	session.close()
	assert session.is_closed() == true
}

fn test_runtime_session_close_is_idempotent_after_host_installs() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	ctx := session.context()
	value := ctx.eval('typeof process + "|" + typeof Buffer') or { panic(err) }
	ctx.end()
	assert value.to_string() == 'object|object'
	value.free()
	session.close()
	session.close()
	assert session.is_closed() == true
}

fn test_script_runtime_session_installs_profile() {
	mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
		process_args: ['inline.js', 'arg-one']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('typeof console + "|" + typeof process + "|" + process.argv.join(",") + "|" + typeof setTimeout') or {
		panic(err)
	}
	ctx.end()
	defer {
		value.free()
	}
	assert value.to_string() == 'object|object|inline.js,arg-one|undefined'
}

fn test_runtime_session_high_level_run_load_and_call() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	value := session.run_module('./tests/runtime_session_module_exports.mjs') or { panic(err) }
	value.free()
	module_exports := session.load_module('./tests/runtime_session_module_exports.mjs') or {
		panic(err)
	}
	defer {
		module_exports.free()
	}
	meaning := module_exports.get('meaning')
	defer {
		meaning.free()
	}
	assert meaning.to_int() == 42
	default_export := module_exports.get('default')
	defer {
		default_export.free()
	}
	label := default_export.get('label')
	defer {
		label.free()
	}
	assert label.to_string() == 'default-export'
	mut module_handle := session.import_module('./tests/runtime_session_module_exports.mjs') or {
		panic(err)
	}
	defer {
		module_handle.close()
	}
	meaning_from_handle := module_handle.get_export('meaning') or { panic(err) }
	defer {
		meaning_from_handle.free()
	}
	assert meaning_from_handle.to_int() == 42
	greet_from_handle := module_handle.call_export('greet', 'handle') or { panic(err) }
	defer {
		greet_from_handle.free()
	}
	assert greet_from_handle.to_string() == 'hello:handle'
	default_method := module_handle.call_default_method('format', 'bridge') or { panic(err) }
	defer {
		default_method.free()
	}
	assert default_method.to_string() == 'default:bridge'
	greet := session.call_module_export('./tests/runtime_session_module_exports.mjs',
		'greet', 'vjsx') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'hello:vjsx'
	default_method_from_session := session.call_default_export_method('./tests/runtime_session_module_exports.mjs',
		'format', 'session') or { panic(err) }
	defer {
		default_method_from_session.free()
	}
	assert default_method_from_session.to_string() == 'default:session'
	value_export := session.call_module_export('./tests/runtime_session_module_exports.mjs',
		'meaning') or { panic(err) }
	defer {
		value_export.free()
	}
	assert value_export.to_int() == 42
}

fn test_runtime_session_plugin_lifecycle_helper() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	mut plugin := session.load_plugin('./tests/runtime_session_plugin.mjs', vjsx.ScriptPluginHooks{}) or {
		panic(err)
	}
	defer {
		plugin.close()
	}
	assert plugin.name().ends_with('tests/runtime_session_plugin.mjs')
	assert plugin.path().ends_with('tests/runtime_session_plugin.mjs')
	assert plugin.capabilities().len == 0
	assert plugin.has_capability('worker') == false
	activate := plugin.activate('host-app') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'activate:host-app:1'
	handle := plugin.handle('job-1') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'handle:job-1:1'
	dispose := plugin.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'dispose:1'
	handle_after_dispose := plugin.handle('job-2') or { panic(err) }
	defer {
		handle_after_dispose.free()
	}
	assert handle_after_dispose.to_string() == 'handle:job-2:0'
}

fn test_runtime_session_plugin_metadata_helpers() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	mut plugin := session.load_plugin('./tests/runtime_session_plugin.mjs', vjsx.ScriptPluginHooks{
		name:         'demo-plugin'
		capabilities: ['serve', 'reload']
	}) or { panic(err) }
	defer {
		plugin.close()
	}
	assert plugin.name() == 'demo-plugin'
	assert plugin.path().ends_with('tests/runtime_session_plugin.mjs')
	assert plugin.capabilities() == ['serve', 'reload']
	assert plugin.has_capability('serve')
	assert plugin.has_capability('reload')
	assert plugin.has_capability('missing') == false
}

fn test_runtime_session_close_auto_disposes_plugin() {
	base_dir := os.join_path(@VMODROOT, 'tests', '.tmp_runtime_session_plugin_cleanup')
	os.mkdir_all(base_dir) or { panic(err) }
	dispose_path := os.join_path(base_dir, 'disposed.txt')
	os.rm(dispose_path) or {}

	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
		fs_roots:     [base_dir]
	})
	mut plugin := session.load_plugin('./tests/runtime_session_plugin_cleanup.mjs', vjsx.ScriptPluginHooks{
		name:         'cleanup-plugin'
		capabilities: ['cleanup']
	}) or { panic(err) }
	activate := plugin.activate(dispose_path) or { panic(err) }
	assert activate.to_string() == 'activate:true'
	activate.free()

	assert plugin.name() == 'cleanup-plugin'
	assert plugin.has_capability('cleanup')
	assert os.exists(dispose_path) == false
	session.close()

	assert plugin.is_closed()
	assert os.exists(dispose_path)
	assert os.read_file(dispose_path) or { panic(err) } == 'disposed'

	os.rm(dispose_path) or {}
	os.rmdir(base_dir) or {}
}

fn runtime_session_test_host_api() vjsx.HostValueBuilder {
	return vjsx.host_object(vjsx.HostObjectField{
		name:  'app'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'name'
			value: vjsx.host_value('host-app')
		})
	}, vjsx.HostObjectField{
		name:  'logger'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'prefix'
			value: vjsx.host_value('log')
		})
	}, vjsx.HostObjectField{
		name:  'math'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'add'
			value: fn (ctx &vjsx.Context) vjsx.Value {
				return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
					return ctx.js_int(args[0].to_int() + args[1].to_int())
				})
			}
		})
	})
}

fn runtime_session_test_host_config() vjsx.HostApiConfig {
	return vjsx.HostApiConfig{
		globals: [
			vjsx.HostGlobalBinding{
				name:  'appName'
				value: vjsx.host_value('embedder')
			},
		]
		modules: [
			vjsx.HostModuleBinding{
				name:    'host-tools'
				install: vjsx.host_module_object(vjsx.HostObjectField{
					name:  'version'
					value: vjsx.host_value('v1')
				}, vjsx.HostObjectField{
					name:  'ping'
					value: fn (ctx &vjsx.Context) vjsx.Value {
						return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
							return ctx.js_string('pong:' + args[0].str())
						})
					}
				})
			},
		]
	}
}

fn test_runtime_session_module_host_call_helpers() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	host_api := runtime_session_test_host_api()
	mut module_handle := session.import_module('./tests/runtime_session_module_host.mjs') or {
		panic(err)
	}
	defer {
		module_handle.close()
	}
	greet_from_handle := module_handle.call_export_with_host('greet', host_api, 'job-a') or {
		panic(err)
	}
	defer {
		greet_from_handle.free()
	}
	assert greet_from_handle.to_string() == 'host-app:job-a:5'
	run_from_handle := module_handle.call_export_method_with_host('worker', 'run', host_api,
		'task-b') or { panic(err) }
	defer {
		run_from_handle.free()
	}
	assert run_from_handle.to_string() == 'log:task-b:9'
	default_from_handle := module_handle.call_default_method_with_host('handle', host_api,
		'task-c') or { panic(err) }
	defer {
		default_from_handle.free()
	}
	assert default_from_handle.to_string() == 'host-app:task-c:log'

	greet := session.call_module_export_with_host('./tests/runtime_session_module_host.mjs',
		'greet', host_api, 'job-d') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'host-app:job-d:5'
	run := session.call_module_method_with_host('./tests/runtime_session_module_host.mjs',
		'worker', 'run', host_api, 'task-e') or { panic(err) }
	defer {
		run.free()
	}
	assert run.to_string() == 'log:task-e:9'
	default_method := session.call_default_export_method_with_host('./tests/runtime_session_module_host.mjs',
		'handle', host_api, 'task-f') or { panic(err) }
	defer {
		default_method.free()
	}
	assert default_method.to_string() == 'host-app:task-f:log'
}

fn test_runtime_session_bound_module_helper() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	host_api := runtime_session_test_host_api()
	mut module_binding := session.import_module_with_host('./tests/runtime_session_module_host.mjs',
		host_api) or { panic(err) }
	defer {
		module_binding.close()
	}
	assert module_binding.path().ends_with('tests/runtime_session_module_host.mjs')
	assert module_binding.has_export('greet')
	assert module_binding.has_export('missing') == false
	greet := module_binding.call_export('greet', 'bound-a') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'host-app:bound-a:5'
	run := module_binding.call_export_method('worker', 'run', 'bound-b') or { panic(err) }
	defer {
		run.free()
	}
	assert run.to_string() == 'log:bound-b:9'
	default_method := module_binding.call_default_method('handle', 'bound-c') or { panic(err) }
	defer {
		default_method.free()
	}
	assert default_method.to_string() == 'host-app:bound-c:log'
	module_binding.close()
	assert module_binding.is_closed()
}

fn test_runtime_session_plugin_explicit_host_context_helper() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	mut plugin := session.load_plugin('./tests/runtime_session_plugin_host.mjs', vjsx.ScriptPluginHooks{}) or {
		panic(err)
	}
	defer {
		plugin.close()
	}
	host_api := runtime_session_test_host_api()
	activate := plugin.activate_with_host(host_api, 'boot') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'log:boot:7'
	handle := plugin.handle_with_host(host_api, 'task-1') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'host-app:task-1:host-app'
	dispose := plugin.dispose_with_host(host_api) or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'dispose:host-app:host-app'
}

fn test_runtime_session_bound_plugin_helper() {
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	host_api := runtime_session_test_host_api()
	mut plugin := session.load_plugin_with_host('./tests/runtime_session_plugin_host.mjs',
		vjsx.ScriptPluginHooks{
		name:         'bound-plugin'
		capabilities: ['lifecycle']
	}, host_api) or { panic(err) }
	defer {
		plugin.close()
	}
	assert plugin.name() == 'bound-plugin'
	assert plugin.path().ends_with('tests/runtime_session_plugin_host.mjs')
	assert plugin.capabilities() == ['lifecycle']
	assert plugin.has_capability('lifecycle')
	assert plugin.has_capability('missing') == false
	activate := plugin.activate('boot') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'log:boot:7'
	handle := plugin.handle('task-2') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'host-app:task-2:host-app'
	dispose := plugin.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'dispose:host-app:host-app'
}

fn test_extension_session_installs_host_api_and_binds_calls() {
	host_api := runtime_session_test_host_api()
	host_config := runtime_session_test_host_config()
	mut extension := runtimejs.new_node_extension_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	}, host_config, host_api)
	defer {
		extension.close()
	}
	mut value := extension.context().eval('
		import hostTools, { version, ping } from "host-tools";
		globalThis.__extension_host_result = [
			globalThis.appName,
			version,
			ping("ok"),
			hostTools.ping("default")
		].join("|");
	',
		vjsx.type_module) or { panic(err) }
	extension.context().end()
	value.free()
	value = extension.context().eval('globalThis.__extension_host_result') or { panic(err) }
	defer {
		value.free()
	}
	assert value.to_string() == 'embedder|v1|pong:ok|pong:default'

	mut module_binding := extension.import_module('./tests/runtime_session_module_host.mjs') or {
		panic(err)
	}
	defer {
		module_binding.close()
	}
	greet := module_binding.call_export('greet', 'ext-a') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'host-app:ext-a:5'
	default_method := extension.call_default_export_method('./tests/runtime_session_module_host.mjs',
		'handle', 'ext-b') or { panic(err) }
	defer {
		default_method.free()
	}
	assert default_method.to_string() == 'host-app:ext-b:log'
}

fn test_extension_session_bound_plugin_lifecycle() {
	host_api := runtime_session_test_host_api()
	host_config := runtime_session_test_host_config()
	mut extension := runtimejs.new_node_extension_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	}, host_config, host_api)
	defer {
		extension.close()
	}
	mut plugin := extension.load_plugin('./tests/runtime_session_plugin_host.mjs', vjsx.ScriptPluginHooks{
		name:         'extension-plugin'
		capabilities: ['hosted']
	}) or { panic(err) }
	defer {
		plugin.close()
	}
	assert plugin.name() == 'extension-plugin'
	assert plugin.has_capability('hosted')
	activate := plugin.activate('boot') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'log:boot:7'
	handle := extension.call_module_export('./tests/runtime_session_module_host.mjs',
		'greet', 'ext-c') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'host-app:ext-c:5'
	dispose := plugin.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'dispose:host-app:host-app'
}

fn test_extension_session_load_extension_contract() {
	host_api := runtime_session_test_host_api()
	host_config := runtime_session_test_host_config()
	mut extension_session := runtimejs.new_node_extension_session(vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	}, host_config, host_api)
	defer {
		extension_session.close()
	}
	mut extension := extension_session.load_extension('./tests/runtimejs_extension_handle.mjs',
		vjsx.ScriptPluginHooks{
		name:         'demo-extension'
		capabilities: ['serve', 'handle']
	}) or { panic(err) }
	defer {
		extension.close()
	}
	assert extension.name() == 'demo-extension'
	assert extension.path().ends_with('tests/runtimejs_extension_handle.mjs')
	assert extension.capabilities() == ['serve', 'handle']
	assert extension.has_capability('serve')
	assert extension.has_capability('missing') == false
	assert extension.has_export('greet')
	assert extension.has_export('service')
	assert extension.has_export('missing') == false

	activate := extension.activate('boot') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'activate:log:boot'
	handle := extension.handle('task-1') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'handle:host-app:task-1:host-app'
	greet := extension.call_export('greet', 'alice') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'greet:host-app:alice'
	run := extension.call_export_method('service', 'run', 'task-2') or { panic(err) }
	defer {
		run.free()
	}
	assert run.to_string() == 'service:log:task-2'
	status := extension.call_default_method('status', 'green') or { panic(err) }
	defer {
		status.free()
	}
	assert status.to_string() == 'status:host-app:green'
	dispose := extension.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'dispose:host-app:host-app'
	extension.close()
	assert extension.is_closed()
}

fn test_extension_session_describe_extension_manifest() {
	host_api := runtime_session_test_host_api()
	host_config := runtime_session_test_host_config()
	mut extension_session := runtimejs.new_node_extension_session(vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	}, host_config, host_api)
	defer {
		extension_session.close()
	}
	manifest := extension_session.describe_extension('./tests/runtimejs_extension_manifest.mjs') or {
		panic(err)
	}
	assert manifest.path.ends_with('tests/runtimejs_extension_manifest.mjs')
	assert manifest.name == 'manifest-extension'
	assert manifest.capabilities == ['search', 'index']
	assert manifest.services.len == 3
	service_names := manifest.services.map(it.name)
	assert 'greet' in service_names
	assert 'taskRunner' in service_names
	assert 'status' in service_names
	assert manifest.activate_export == 'boot'
	assert manifest.handle_export == 'run'
	assert manifest.dispose_export == 'teardown'
}

fn test_extension_session_load_extension_uses_manifest_hooks() {
	host_api := runtime_session_test_host_api()
	host_config := runtime_session_test_host_config()
	mut extension_session := runtimejs.new_node_extension_session(vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	}, host_config, host_api)
	defer {
		extension_session.close()
	}
	mut extension := extension_session.load_extension('./tests/runtimejs_extension_manifest.mjs',
		vjsx.ScriptPluginHooks{}) or { panic(err) }
	defer {
		extension.close()
	}
	assert extension.name() == 'manifest-extension'
	assert extension.capabilities() == ['search', 'index']
	assert extension.has_capability('search')
	assert extension.services().len == 3
	assert extension.has_service('greet')
	assert extension.has_service('taskRunner')
	assert extension.has_service('status')
	assert extension.has_service('missing') == false
	activate := extension.activate('boot-job') or { panic(err) }
	defer {
		activate.free()
	}
	assert activate.to_string() == 'boot:host-app:boot-job'
	handle := extension.handle('task-9') or { panic(err) }
	defer {
		handle.free()
	}
	assert handle.to_string() == 'run:log:task-9:host-app:boot-job'
	greet := extension.call_export('greet', 'alice') or { panic(err) }
	defer {
		greet.free()
	}
	assert greet.to_string() == 'hello:host-app:alice'
	service_run := extension.call_service('taskRunner', 'task-10') or { panic(err) }
	defer {
		service_run.free()
	}
	assert service_run.to_string() == 'service:log:task-10'
	service_status := extension.call_service('status', 'green') or { panic(err) }
	defer {
		service_status.free()
	}
	assert service_status.to_string() == 'status:host-app:green'
	dispose := extension.dispose() or { panic(err) }
	defer {
		dispose.free()
	}
	assert dispose.to_string() == 'teardown:host-app:host-app:boot-job'
}
