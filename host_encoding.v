module vjsx

import encoding.iconv

// Shared text encoding/decoding host functions.
// Used by web.encoding_boot, host_fetch.fetch_encoding_boot,
// and runtimejs.cli_browser_encoding_boot.

@[manualfree]
pub fn host_text_encode(this Value, args []Value) Value {
	uint_cls := this.ctx.js_global('Uint8Array')
	defer {
		uint_cls.free()
	}
	if args.len == 0 || args[0].is_undefined() {
		return uint_cls.new()
	}
	arr_buf := this.ctx.js_array_buffer(args[0].str().bytes())
	defer {
		arr_buf.free()
	}
	return uint_cls.new(arr_buf)
}

@[manualfree]
pub fn host_text_encode_into(this Value, args []Value) Value {
	if args.len != 2 {
		err := this.ctx.js_type_error(message: 'expected args 2 but got ${args.len}')
		return this.ctx.js_throw(err)
	}
	buf := host_text_encode(this, args)
	defer {
		buf.free()
	}
	obj := this.ctx.js_object()
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
	return obj
}

@[manualfree]
pub fn host_text_decode(this Value, args []Value) Value {
	if args.len == 0 || args[0].is_undefined() {
		return this.ctx.js_string('')
	}
	bytes := host_decode_text_bytes(this, args[0]) or {
		err_value := this.ctx.js_type_error(message: err.msg())
		return this.ctx.js_throw(err_value)
	}
	return this.ctx.js_string(bytes.bytestr())
}

pub fn host_decode_text_bytes(this Value, value Value) ![]u8 {
	if value.instanceof('ArrayBuffer') {
		return value.to_bytes()
	}
	array_buffer := this.ctx.js_global('ArrayBuffer')
	defer {
		array_buffer.free()
	}
	is_view_value := array_buffer.call('isView', value)
	defer {
		is_view_value.free()
	}
	if is_view_value.to_bool() && !value.instanceof('DataView') {
		buf := value.get('buffer')
		defer {
			buf.free()
		}
		return buf.to_bytes()
	}
	return error('argument is not an ArrayBuffer or TypedArray')
}

@[manualfree]
pub fn host_decode_text(this Value, args []Value) Value {
	if args.len < 2 {
		err := this.ctx.js_type_error(message: 'expected args 2 but got ${args.len}')
		return this.ctx.js_throw(err)
	}
	label := args[0].str()
	bytes := host_decode_text_bytes(this, args[1]) or {
		err_value := this.ctx.js_type_error(message: err.msg())
		return this.ctx.js_throw(err_value)
	}
	if label in ['utf-8', 'utf8'] {
		return this.ctx.js_string(bytes.bytestr())
	}
	decoded := iconv.encoding_to_vstring(bytes, label) or {
		err_value := this.ctx.js_type_error(message: err.msg())
		return this.ctx.js_throw(err_value)
	}
	return this.ctx.js_string(decoded)
}
