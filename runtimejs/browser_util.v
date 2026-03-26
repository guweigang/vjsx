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
	boot.set('text_encode', ctx.js_function_this(fn [ctx] (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		uint_cls := ctx.js_global('Uint8Array')
		if args.len == 0 || args[0].is_undefined() {
			return uint_cls.new()
		}
		arr_buf := ctx.js_array_buffer(args[0].str().bytes())
		uint := uint_cls.new(arr_buf)
		arr_buf.free()
		return uint
	}))
	boot.set('text_decode', ctx.js_function_this(fn [ctx] (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		if args.len == 0 || args[0].is_undefined() {
			return ctx.js_string('')
		}
		mut buf := args[0]
		if buf.instanceof('ArrayBuffer') {
			return ctx.js_string(buf.to_bytes().bytestr())
		}
		if cli_browser_is_typed_array(this, args) {
			buf = buf.get('buffer')
			ret := ctx.js_string(buf.to_bytes().bytestr())
			buf.free()
			return ret
		}
		err := ctx.js_type_error(message: 'args[0] not TypedArray')
		return ctx.js_throw(err)
	}))
	boot.set('text_encode_into', ctx.js_function_this(fn [ctx] (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		if args.len != 2 {
			err := ctx.js_type_error(message: 'expected args 2 but got ${args.len}')
			return ctx.js_throw(err)
		}
		uint_cls := ctx.js_global('Uint8Array')
		arr_buf := ctx.js_array_buffer(args[0].str().bytes())
		buf := uint_cls.new(arr_buf)
		arr_buf.free()
		obj := ctx.js_object()
		text_len := args[0].len()
		buf_len := buf.len()
		arr_len := args[1].len()
		obj.set('read', text_len)
		obj.set('written', buf_len)
		if buf_len > arr_len {
			read_val := arr_len / buf_len * obj.get('read').to_int()
			obj.set('read', read_val)
			obj.set('written', arr_len)
		}
		args[1].call('set', buf, 0)
		buf.free()
		return obj
	}))
}
