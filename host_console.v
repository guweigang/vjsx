module vjsx

// Install `console.log(...)` and `console.error(...)`.
pub fn (ctx &Context) install_console(log_fn HostLogFn, error_fn HostLogFn) {
	global := ctx.js_global()
	console := ctx.js_object()
	console.set('log', ctx.js_function(fn [ctx, log_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		log_fn(line)
		return ctx.js_undefined()
	}))
	console.set('error', ctx.js_function(fn [ctx, error_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		error_fn(line)
		return ctx.js_undefined()
	}))
	console.set('warn', ctx.js_function(fn [ctx, error_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		error_fn(line)
		return ctx.js_undefined()
	}))
	global.set('console', console)
	console.free()
	global.free()
}
