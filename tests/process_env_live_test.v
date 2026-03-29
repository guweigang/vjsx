import os
import vjsx

fn test_process_env_reads_live_host_values() {
	key := 'VJSX_PROCESS_ENV_LIVE_TEST'
	os.unsetenv(key)
	mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
		os.unsetenv(key)
	}
	ctx := session.context()
	initial := ctx.eval('String(process.env.VJSX_PROCESS_ENV_LIVE_TEST)') or { panic(err) }
	ctx.end()
	assert initial.to_string() == 'undefined'
	initial.free()
	os.setenv(key, 'updated-from-host', true)
	updated := ctx.eval('process.env.VJSX_PROCESS_ENV_LIVE_TEST') or { panic(err) }
	ctx.end()
	assert updated.to_string() == 'updated-from-host'
	updated.free()
}
