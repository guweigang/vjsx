module vjsx

import net.http

fn fetch_get_bootstrap(ctx &Context) (Value, Value) {
	glob := ctx.js_global()
	boot := glob.get('__bootstrap')
	if boot.is_undefined() {
		boot.free()
		glob.set('__bootstrap', ctx.js_object())
	}
	return glob, glob.get('__bootstrap')
}

fn fetch_is_object(this Value, args []Value) Value {
	val := args[0]
	if val.is_undefined() || val.is_null() {
		return this.ctx.js_bool(false)
	}
	ctor := val.get('constructor')
	defer {
		ctor.free()
	}
	if ctor.is_undefined() || ctor.is_null() {
		return this.ctx.js_bool(false)
	}
	name := ctor.get('name')
	defer {
		name.free()
	}
	return this.ctx.js_bool(name.str() == 'Object')
}

fn fetch_is_type_object(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_object())
}

fn fetch_is_array(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_array())
}

fn fetch_is_string(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_string())
}

fn fetch_is_number(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_number())
}

fn fetch_is_bool(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_bool())
}

fn fetch_is_func(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].is_function())
}

fn fetch_is_regexp(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].instanceof('RegExp'))
}

fn fetch_is_array_buffer(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].instanceof('ArrayBuffer'))
}

fn fetch_is_promise(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].instanceof('Promise'))
}

fn fetch_is_typed_array_bool(this Value, args []Value) bool {
	val := args[0]
	buf := this.ctx.js_global('ArrayBuffer')
	defer {
		buf.free()
	}
	call_is_view := buf.call('isView', val)
	defer {
		call_is_view.free()
	}
	is_view := call_is_view.to_bool()
	is_data_view := val.instanceof('DataView')
	return is_view && !is_data_view
}

fn fetch_is_date(this Value, args []Value) Value {
	return this.ctx.js_bool(args[0].instanceof('Date'))
}

fn fetch_is_redirect(this Value, args []Value) Value {
	code := args[0].to_int()
	return this.ctx.js_bool(code == 301 || code == 302 || code == 303 || code == 307 || code == 308)
}

fn fetch_is_typed_array(this Value, args []Value) Value {
	return this.ctx.js_bool(fetch_is_typed_array_bool(this, args))
}

fn fetch_util_boot(ctx &Context, boot Value) {
	obj := ctx.js_object()
	obj.set('isObject', ctx.js_function_this(fetch_is_object))
	obj.set('isTypeObject', ctx.js_function_this(fetch_is_type_object))
	obj.set('isArray', ctx.js_function_this(fetch_is_array))
	obj.set('isString', ctx.js_function_this(fetch_is_string))
	obj.set('isNumber', ctx.js_function_this(fetch_is_number))
	obj.set('isBool', ctx.js_function_this(fetch_is_bool))
	obj.set('isFunc', ctx.js_function_this(fetch_is_func))
	obj.set('isRegExp', ctx.js_function_this(fetch_is_regexp))
	obj.set('isArrayBuffer', ctx.js_function_this(fetch_is_array_buffer))
	obj.set('isPromise', ctx.js_function_this(fetch_is_promise))
	obj.set('isTypedArray', ctx.js_function_this(fetch_is_typed_array))
	obj.set('isDate', ctx.js_function_this(fetch_is_date))
	obj.set('isRedirect', ctx.js_function_this(fetch_is_redirect))
	boot.set('util', obj)
	obj.free()
}

@[manualfree]
fn fetch_text_encode(this Value, args []Value) Value {
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
fn fetch_text_encode_into(this Value, args []Value) Value {
	if args.len != 2 {
		err := this.ctx.js_type_error(message: 'expected args 2 but got ${args.len}')
		return this.ctx.js_throw(err)
	}
	buf := fetch_text_encode(this, args)
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
fn fetch_text_decode(this Value, args []Value) Value {
	if args.len == 0 || args[0].is_undefined() {
		return this.ctx.js_string('')
	}
	mut buf := args[0]
	if buf.instanceof('ArrayBuffer') {
		return this.ctx.js_string(buf.to_bytes().bytestr())
	}
	if fetch_is_typed_array_bool(this, args) {
		buf = buf.get('buffer')
		defer {
			buf.free()
		}
		return this.ctx.js_string(buf.to_bytes().bytestr())
	}
	err := this.ctx.js_type_error(message: 'args[0] not TypedArray')
	return this.ctx.js_throw(err)
}

fn fetch_encoding_boot(ctx &Context, boot Value) {
	boot.set('text_encode', ctx.js_function_this(fetch_text_encode))
	boot.set('text_decode', ctx.js_function_this(fetch_text_decode))
	boot.set('text_encode_into', ctx.js_function_this(fetch_text_encode_into))
}

fn fetch_core(this Value, args []Value) Value {
	mut error := this.ctx.js_undefined()
	promise := this.ctx.js_promise()
	if args.len == 0 {
		error = this.ctx.js_error(message: 'url is required', name: 'TypeError')
		return promise.reject(error)
	}
	url := args[0].str()
	opts := if args.len > 1 { args[1].dup_value() } else { this.ctx.js_object() }
	defer {
		opts.free()
	}
	method := opts.get('method')
	defer {
		method.free()
	}
	headers := opts.get('headers')
	defer {
		headers.free()
	}
	raw_body := opts.get('body')
	defer {
		raw_body.free()
	}
	boundary := opts.get('boundary')
	defer {
		boundary.free()
	}
	mut hd := http.new_header()
	if headers.is_object() {
		props := headers.property_names() or {
			error = this.ctx.js_error(message: err.msg())
			return promise.reject(error)
		}
		for data in props {
			key := data.atom.str()
			val := headers.get(key)
			hd.set_custom(key, val.str()) or {
				val.free()
				error = this.ctx.js_error(message: err.msg())
				return promise.reject(error)
			}
			val.free()
		}
	}
	request_method := http.Method.from(method.str().to_lower()) or { http.Method.get }
	body := raw_body.str()
	mut resp := http.Response{}
	if boundary.is_undefined() {
		resp = http.fetch(
			url:    url
			method: request_method
			header: hd
			data:   body
		) or {
			error = this.ctx.js_error(message: err.msg())
			return promise.reject(error)
		}
	} else {
		form, files := http.parse_multipart_form(body, '----formdata-' + boundary.str())
		resp = http.post_multipart_form(url, form: form, header: hd, files: files) or {
			error = this.ctx.js_error(message: err.msg())
			return promise.reject(error)
		}
	}
	obj_header := this.ctx.js_object()
	for key in resp.header.keys() {
		vals := resp.header.custom_values(key)
		obj_header.set(key, vals.join('; '))
	}
	obj := this.ctx.js_object()
	obj.set('body', resp.body)
	obj.set('status', resp.status_code)
	obj.set('status_message', resp.status_msg)
	obj.set('header', obj_header)
	obj_header.free()
	return promise.resolve(obj)
}

fn fetch_boot(ctx &Context, boot Value) {
	boot.set('core_fetch', ctx.js_function_this(fetch_core))
}

pub fn (ctx &Context) install_fetch_globals() {
	glob, boot := fetch_get_bootstrap(ctx)
	fetch_util_boot(ctx, boot)
	fetch_encoding_boot(ctx, boot)
	fetch_boot(ctx, boot)
	ctx.eval_runtime_file('web/js/util.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/stream.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/encoding.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/url.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/url_pattern.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/blob.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/form_data.js', type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/fetch.js', type_module) or { panic(err) }
	glob.delete('__bootstrap')
	boot.free()
	glob.free()
}
