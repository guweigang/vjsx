module vjsx

import encoding.base64

// Install a tiny `atob` and `Buffer` global for Node/browser-leaning packages.
pub fn (ctx &Context) install_binary_globals() {
	global := ctx.js_global()
	global.set('atob', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw('args[0] is required')
		}
		ret := base64.decode_str(args[0].str())
		return ctx.js_string(ret)
	}))
	global.free()
	ctx.eval_file('${@VMODROOT}/web/js/buffer.js', type_module) or { panic(err) }
}

// Install timer globals (`setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`).
pub fn (ctx &Context) install_timer_globals() {
	ctx.eval_file('${@VMODROOT}/web/js/timer.js', type_module) or { panic(err) }
}

// Install URL globals (`URL`, `URLSearchParams`, `URLPattern`).
pub fn (ctx &Context) install_url_globals() {
	ctx.eval_file('${@VMODROOT}/web/js/url.js', type_module) or { panic(err) }
	ctx.eval_file('${@VMODROOT}/web/js/url_pattern.js', type_module) or { panic(err) }
}
