import os
import vjsx
import runtimejs

const runtime_session_test_wake_log_env = 'VJSX_RUNTIME_SESSION_TEST_WAKE_LOG'

fn runtime_session_test_reset_wakeup_hooks(path string) {
	os.setenv(runtime_session_test_wake_log_env, path, true)
	if os.exists(path) {
		os.rm(path) or {}
	}
}

fn runtime_session_test_append_wakeup_log(line string) {
	path := os.getenv_opt(runtime_session_test_wake_log_env) or { return }
	existing := os.read_file(path) or { '' }
	mut next := line
	if existing != '' {
		next = existing + '\n' + line
	}
	os.write_file(path, next) or {}
}

fn runtime_session_test_read_wakeup_log(path string) []string {
	if !os.exists(path) {
		return []string{}
	}
	raw := os.read_file(path) or { return []string{} }
	if raw.trim_space() == '' {
		return []string{}
	}
	return raw.split_into_lines()
}

fn runtime_session_test_record_wake(req vjsx.RuntimeSessionWakeRequest) {
	runtime_session_test_append_wakeup_log('wake:${req.session_id}:${req.wake_at_ms}:${req.generation}:${req.reason}')
}

fn runtime_session_test_record_wake_cancel(req vjsx.RuntimeSessionWakeCancelRequest) {
	runtime_session_test_append_wakeup_log('cancel:${req.session_id}:${req.generation}:${req.reason}')
}

fn runtime_session_test_record_diagnostic(diagnostic vjsx.RuntimeSessionDiagnostic) {
	runtime_session_test_append_wakeup_log('diagnostic:${diagnostic.session_id}:${diagnostic.kind}:${diagnostic.at_ms}:${diagnostic.message.contains('async boom')}')
}

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

fn test_runtime_session_pump_apis_drive_ready_tasks() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('
		globalThis.__pump_value = "pending";
		Promise.resolve().then(() => {
			globalThis.__pump_value = "done";
		});
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	assert session.has_ready_task() == true
	assert session.drain_ready_tasks() or { panic(err) } == 1
	assert session.has_ready_task() == false
	result := ctx.js_global('__pump_value')
	defer {
		result.free()
	}
	assert result.to_string() == 'done'
}

fn test_runtime_session_pump_once_runs_single_job() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('
		globalThis.__pump_once_steps = [];
		Promise.resolve()
			.then(() => globalThis.__pump_once_steps.push("first"))
			.then(() => globalThis.__pump_once_steps.push("second"));
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	assert session.pump_once() or { panic(err) }
	after_first := ctx.eval('globalThis.__pump_once_steps.join(",")') or { panic(err) }
	defer {
		after_first.free()
	}
	assert after_first.to_string() == 'first'
	assert session.pump_once() or { panic(err) }
	after_second := ctx.eval('globalThis.__pump_once_steps.join(",")') or { panic(err) }
	defer {
		after_second.free()
	}
	assert after_second.to_string() == 'first,second'
	assert (session.pump_once() or { panic(err) }) == false
}

fn test_runtime_session_records_async_job_diagnostics() {
	log_path := os.join_path(os.temp_dir(), 'vjsx_runtime_session_test_diagnostics.log')
	runtime_session_test_reset_wakeup_hooks(log_path)
	mut session := vjsx.new_runtime_session()
	defer {
		os.unsetenv(runtime_session_test_wake_log_env)
		os.rm(log_path) or {}
		session.close()
	}
	session.set_diagnostic_handler(runtime_session_test_record_diagnostic)
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:     fn () i64 {
			return 12345
		}
		session_id: 'diagnostic-session'
	})
	ctx := session.context()
	value := ctx.eval('
		globalThis.__diagnostic_rejected = Promise.resolve().then(() => {
			throw new Error("async boom");
		});
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	assert session.diagnostic_error_count() == 0
	promise_value := ctx.js_global('__diagnostic_rejected')
	defer {
		promise_value.free()
	}
	session.resolve_value(promise_value) or { assert err.msg().contains('async boom') }
	assert session.diagnostic_error_count() == 1
	diagnostic := session.last_diagnostic() or { panic(err) }
	assert diagnostic.session_id == 'diagnostic-session'
	assert diagnostic.kind == 'resolve_value'
	assert diagnostic.message.contains('async boom')
	assert diagnostic.at_ms == 12345
	snapshot := session.debug_snapshot()
	assert snapshot.async_error_count == 1
	assert snapshot.last_error_message.contains('async boom')
	diagnostic_log := runtime_session_test_read_wakeup_log(log_path)
	assert diagnostic_log.len == 1
	assert diagnostic_log[0] == 'diagnostic:diagnostic-session:resolve_value:12345:true'
	session.clear_diagnostics()
	assert session.diagnostic_error_count() == 0
}

fn test_runtime_session_diagnostics_are_bounded() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_limits(vjsx.RuntimeSessionLimits{
		max_diagnostics: 2
	})
	session.call_global('missing_a') or {}
	session.call_global('missing_b') or {}
	session.call_global('missing_c') or {}
	assert session.diagnostic_error_count() == 2
	assert session.dropped_diagnostic_count() == 1
	diagnostics := session.diagnostics()
	assert diagnostics.len == 2
	assert diagnostics[0].message.contains('missing_b')
	assert diagnostics[1].message.contains('missing_c')
	snapshot := session.debug_snapshot()
	assert snapshot.async_error_count == 2
	assert snapshot.dropped_diagnostic_count == 1
}

fn test_runtime_session_timer_wakeup_hints_are_bounded() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_limits(vjsx.RuntimeSessionLimits{
		max_timer_wakeup_hints: 1
	})
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:     fn () i64 {
			return 8000
		}
		session_id: 'limit-session'
	})
	assert session.request_timer_wakeup_after('timer-a', 10) == 8010
	assert session.request_timer_wakeup_after('timer-b', 20) == -1
	assert session.rejected_timer_wakeup_hint_count() == 1
	assert session.diagnostic_error_count() == 1
	diagnostic := session.last_diagnostic() or { panic(err) }
	assert diagnostic.kind == 'timer_wakeup_hint_limit'
	snapshot := session.debug_snapshot()
	assert snapshot.timer_wakeup_hint_count == 1
	assert snapshot.timer_wakeup_hint_limit == 1
	assert snapshot.rejected_timer_wakeup_hint_count == 1
	assert snapshot.async_error_count == 1
}

fn test_runtime_session_event_loop_config_tracks_wakeup_contract() {
	log_path := os.join_path(os.temp_dir(), 'vjsx_runtime_session_test_wakeup.log')
	runtime_session_test_reset_wakeup_hooks(log_path)
	mut session := vjsx.new_runtime_session()
	defer {
		os.unsetenv(runtime_session_test_wake_log_env)
		os.rm(log_path) or {}
		session.close()
	}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:               fn () i64 {
			return 4242
		}
		wake_fn:              runtime_session_test_record_wake
		cancel_wake_fn:       runtime_session_test_record_wake_cancel
		runtime_owned_timers: true
		session_id:           'session-a'
	})
	assert session.runtime_owns_timers() == true
	assert session.now_ms() == 4242
	assert session.has_pending_wakeup() == false
	assert session.has_ready_tasks() == false
	assert session.needs_wakeup() == false
	assert session.next_wakeup_at() == none
	session.request_wakeup_at(9001, 'timer-ready')
	assert session.has_pending_wakeup()
	assert session.needs_wakeup()
	assert session.next_wakeup_at() or { panic(err) } == 9001
	mut wake_log := runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 1
	assert wake_log[0] == 'wake:session-a:9001:1:timer-ready'
	assert session.wakeup_generation() == 1
	session.request_wakeup_at(9001, 'same-wakeup')
	wake_log = runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 1
	assert session.wakeup_generation() == 1
	requested_after := session.request_wakeup_after(250, 'delay-ready')
	assert requested_after == 4492
	assert session.next_wakeup_at() or { panic(err) } == 4492
	wake_log = runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 2
	assert wake_log[1] == 'wake:session-a:4492:2:delay-ready'
	assert session.wakeup_generation() == 2
	config := session.event_loop_config()
	assert config.session_id == 'session-a'
	assert config.runtime_owned_timers == true
	session.clear_wakeup_request()
	assert session.has_pending_wakeup() == false
	assert session.needs_wakeup() == false
	assert session.next_wakeup_at() == none
	wake_log = runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 3
	assert wake_log[2] == 'cancel:session-a:2:cleared'
	assert session.wakeup_generation() == 0
}

fn test_runtime_session_timer_wrapper_tracks_quickjs_wakeup_hints() {
	log_path := os.join_path(os.temp_dir(), 'vjsx_runtime_session_test_timer_wakeup.log')
	runtime_session_test_reset_wakeup_hooks(log_path)
	mut session := vjsx.new_runtime_session()
	defer {
		os.unsetenv(runtime_session_test_wake_log_env)
		os.rm(log_path) or {}
		session.close()
	}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:         fn () i64 {
			return 1000
		}
		wake_fn:        runtime_session_test_record_wake
		cancel_wake_fn: runtime_session_test_record_wake_cancel
		session_id:     'timer-session'
	})
	ctx := session.context()
	ctx.install_timer_globals()
	value := ctx.eval('
		globalThis.__timer_wrapper_value = "pending";
		globalThis.__timer_wrapper_handle = setTimeout(() => {
			globalThis.__timer_wrapper_value = "done";
		}, 10);
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	wake_log := runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 1
	assert wake_log[0] == 'wake:timer-session:1010:1:timer'
	assert session.next_wakeup_at() or { panic(err) } == 1010
	assert session.wakeup_generation() == 1
	session.pump_until_idle()
	result := ctx.js_global('__timer_wrapper_value')
	defer {
		result.free()
	}
	assert result.to_string() == 'done'
	after_pump_log := runtime_session_test_read_wakeup_log(log_path)
	assert after_pump_log.len == 2
	assert after_pump_log[1] == 'cancel:timer-session:1:cleared'
	assert session.next_wakeup_at() == none
}

fn test_runtime_session_close_clears_event_loop_wakeup_state() {
	log_path := os.join_path(os.temp_dir(), 'vjsx_runtime_session_test_close_wakeup.log')
	runtime_session_test_reset_wakeup_hooks(log_path)
	mut session := vjsx.new_runtime_session()
	defer {
		os.unsetenv(runtime_session_test_wake_log_env)
		os.rm(log_path) or {}
		session.close()
	}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:         fn () i64 {
			return 5000
		}
		wake_fn:        runtime_session_test_record_wake
		cancel_wake_fn: runtime_session_test_record_wake_cancel
		session_id:     'closing-session'
	})
	session.request_timer_wakeup_after('timer-a', 25)
	assert session.has_pending_wakeup()
	assert session.next_wakeup_at() or { panic(err) } == 5025
	session.close()
	assert session.is_closed()
	assert session.has_pending_wakeup() == false
	assert session.needs_wakeup() == false
	assert session.next_wakeup_at() == none
	assert session.request_wakeup_after(10, 'after-close') == -1
	assert session.request_timer_wakeup_after('timer-b', 10) == -1
	wake_log := runtime_session_test_read_wakeup_log(log_path)
	assert wake_log.len == 2
	assert wake_log[0] == 'wake:closing-session:5025:1:timer'
	assert wake_log[1] == 'cancel:closing-session:1:cleared'
}

fn test_runtime_session_debug_snapshot_reports_async_state() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	session.configure_event_loop(vjsx.RuntimeSessionEventLoopConfig{
		now_fn:               fn () i64 {
			return 7000
		}
		runtime_owned_timers: true
		session_id:           'debug-session'
	})
	ctx := session.context()
	value := ctx.eval('Promise.resolve().then(() => {})') or { panic(err) }
	session.request_timer_wakeup_after('timer-a', 40)
	session.request_timer_wakeup_after('timer-b', 10)
	snapshot := session.debug_snapshot()
	assert snapshot.session_id == 'debug-session'
	assert snapshot.closed == false
	assert snapshot.runtime_owned_timers == true
	assert snapshot.has_ready_task == true
	assert snapshot.has_pending_wakeup == true
	assert snapshot.needs_wakeup == true
	assert snapshot.next_wakeup_at_ms == 7010
	assert snapshot.wakeup_generation == 2
	assert snapshot.timer_wakeup_hint_count == 2
	assert snapshot.next_timer_wakeup_at_ms == 7010
	value.free()
	session.close()
	closed_snapshot := session.debug_snapshot()
	assert closed_snapshot.closed == true
	assert closed_snapshot.has_ready_task == false
	assert closed_snapshot.has_pending_wakeup == false
	assert closed_snapshot.needs_wakeup == false
	assert closed_snapshot.next_wakeup_at_ms == -1
	assert closed_snapshot.wakeup_generation == 0
	assert closed_snapshot.timer_wakeup_hint_count == 0
	assert closed_snapshot.next_timer_wakeup_at_ms == -1
}

fn test_runtime_session_resolve_value_and_call_global_resolved() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	setup := ctx.eval('
		globalThis.__resolve_direct = Promise.resolve("settled");
		globalThis.__resolve_fn = (value) => Promise.resolve("ok:" + value);
		globalThis.__plain_fn = (value) => "plain:" + value;
	') or {
		panic(err)
	}
	defer {
		setup.free()
	}
	promise_value := ctx.js_global('__resolve_direct')
	defer {
		promise_value.free()
	}
	resolved := session.resolve_value(promise_value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'settled'
	from_global := session.call_global_resolved('__resolve_fn', 'demo') or { panic(err) }
	defer {
		from_global.free()
	}
	assert from_global.to_string() == 'ok:demo'
	plain_global := session.call_global_resolved('__plain_fn', 'demo') or { panic(err) }
	defer {
		plain_global.free()
	}
	assert plain_global.to_string() == 'plain:demo'
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
