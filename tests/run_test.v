import vjs

fn test_run_helpers() {
	rt := vjs.new_runtime()
	ctx := rt.new_context()

	value := ctx.run('1 + 2') or { panic(err) }
	assert value.to_int() == 3
	value.free()

	file_value := ctx.run_file('./tests/test.js') or { panic(err) }
	assert file_value.to_string() == 'test foo'
	file_value.free()

	module_value := ctx.run_module('globalThis.__run_mod = await Promise.resolve("ok")', 'inline.js') or {
		panic(err)
	}
	assert module_value.is_undefined()
	module_value.free()
	mod_value := ctx.js_global('__run_mod')
	assert mod_value.to_string() == 'ok'
	mod_value.free()

	ctx.free()
	rt.free()
}
