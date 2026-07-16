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
	global.set('structuredClone', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		source := args[0].json_stringify()
		return ctx.eval('(' + source + ')') or { ctx.js_throw(err.msg()) }
	}))
	global.free()
	ctx.eval_runtime_file('web/js/typed_array.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/buffer.js', type_module) or { panic(err) }
}

// Install timer globals (`setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`).
pub fn (ctx &Context) install_timer_globals() {
	ctx.eval_runtime_file('web/js/timer.js', type_module) or { panic(err) }
}

// Install event globals (`Event`, `CustomEvent`, `EventTarget`).
pub fn (ctx &Context) install_event_globals() {
	ctx.eval_runtime_file('web/js/event.js', type_module) or { panic(err) }
}

// Install cancellation globals (`AbortController`, `AbortSignal`).
pub fn (ctx &Context) install_abort_globals() {
	ctx.eval_runtime_file('web/js/abort.js', type_module) or { panic(err) }
}

// Install URL globals (`URL`, `URLSearchParams`, `URLPattern`).
pub fn (ctx &Context) install_url_globals() {
	ctx.eval_runtime_file('web/js/url.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/url_pattern.js', type_module) or { panic(err) }
}

// Install text encoding globals (`TextEncoder`, `TextDecoder`).
pub fn (ctx &Context) install_encoding_globals() {
	glob, boot := fetch_get_bootstrap(ctx)
	boot.set('text_encode', ctx.js_function_this(host_text_encode))
	boot.set('text_decode', ctx.js_function_this(host_text_decode))
	boot.set('decode_text', ctx.js_function_this(host_decode_text))
	boot.set('text_encode_into', ctx.js_function_this(host_text_encode_into))
	ctx.eval_runtime_file('web/js/encoding.js', type_module) or { panic(err) }
	glob.delete('__bootstrap')
	boot.free()
	glob.free()
}

// Install a small `Intl.DateTimeFormat` subset.
pub fn (ctx &Context) install_intl_globals() {
	glob, boot := fetch_get_bootstrap(ctx)
	boot.set('intl_date_time_parts', ctx.js_function_this(host_intl_date_time_parts))
	ctx.eval_runtime_file('web/js/intl.js', type_module) or { panic(err) }
	glob.delete('__bootstrap')
	boot.free()
	glob.free()
}
