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
