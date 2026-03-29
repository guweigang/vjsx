import vjsx

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
