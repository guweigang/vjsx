module vjsx

import os

// Install a small `process` global with `cwd()` and `env`.
pub fn (ctx &Context) install_process(args []string) {
	global := ctx.js_global()
	process := ctx.js_object()
	process.set('cwd', ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(os.getwd())
	}))
	argv := ctx.js_array()
	for i, arg in args {
		argv.set(i, arg)
	}
	process.set('argv', argv)
	env := ctx.js_object()
	for key, val in os.environ() {
		env.set(key, val)
	}
	process.set('env', env)
	global.set('process', process)
	argv.free()
	env.free()
	process.free()
	global.free()
}
