module runtimejs

import vjsx

fn cli_browser_util_boot(ctx &vjsx.Context, boot vjsx.Value) {
	obj := ctx.js_object()
	obj.set('isArrayBuffer', ctx.js_function_this(fn (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		return this.ctx.js_bool(args[0].instanceof('ArrayBuffer'))
	}))
	obj.set('isTypedArray', ctx.js_function_this(fn (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		return this.ctx.js_bool(cli_browser_is_typed_array(this, args))
	}))
	obj.set('isRedirect', ctx.js_function_this(fn (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		code := args[0].to_int()
		return this.ctx.js_bool(code == 301 || code == 302 || code == 303 || code == 307
			|| code == 308)
	}))
	boot.set('util', obj)
}

fn cli_browser_encoding_boot(ctx &vjsx.Context, boot vjsx.Value) {
	boot.set('text_encode', ctx.js_function_this(vjsx.host_text_encode))
	boot.set('text_decode', ctx.js_function_this(vjsx.host_text_decode))
	boot.set('decode_text', ctx.js_function_this(vjsx.host_decode_text))
	boot.set('text_encode_into', ctx.js_function_this(vjsx.host_text_encode_into))
}
