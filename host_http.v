module vjsx

import net.http

fn http_header_object(ctx &Context, header http.Header) Value {
	obj := ctx.js_object()
	for key in header.keys() {
		obj.set(key.to_lower(), header.custom_values(key).join(', '))
	}
	return obj
}

fn http_request_object(ctx &Context) Value {
	request := ctx.js_object()
	error_listeners := ctx.js_array()
	on_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len < 2 || !args[1].is_function() {
			return ctx.js_throw(ctx.js_error(
				message: 'event name and callback are required'
				name:    'TypeError'
			))
		}
		if args[0].str() != 'error' {
			return this.dup_value()
		}
		listeners := this.get('_vjsxErrorListeners')
		listeners.set(listeners.len(), args[1])
		pending_error := this.get('_vjsxPendingError')
		if !pending_error.is_undefined() && !pending_error.is_null() {
			ctx.call_this(this, args[1], pending_error) or {}
		}
		pending_error.free()
		listeners.free()
		return this.dup_value()
	})
	request.set('_vjsxErrorListeners', error_listeners)
	request.set('_vjsxPendingError', ctx.js_undefined())
	request.set('on', on_fn)
	error_listeners.free()
	on_fn.free()
	return request
}

fn http_response_object(ctx &Context, response http.Response, body_bytes []u8) Value {
	obj := ctx.js_object()
	headers := http_header_object(ctx, response.header)
	pipe_fn := ctx.js_function_this(fn [ctx, body_bytes] (this Value, args []Value) Value {
		if args.len == 0 || !args[0].is_object() {
			return ctx.js_throw(ctx.js_error(
				message: 'destination stream is required'
				name:    'TypeError'
			))
		}
		dest := args[0]
		path_value := dest.get('_vjsxPath')
		if path_value.is_undefined() || path_value.is_null() {
			path_value.free()
			return ctx.js_throw(ctx.js_error(
				message: 'unsupported write stream destination'
				name:    'TypeError'
			))
		}
		target := path_value.str()
		path_value.free()
		closed_value := dest.get('_vjsxClosed')
		is_closed := closed_value.to_bool()
		closed_value.free()
		if is_closed {
			return ctx.js_throw(ctx.js_error(message: 'write after close', name: 'Error'))
		}
		fs_append_bytes(target, body_bytes) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		fs_emit_finish(ctx, dest) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return dest.dup_value()
	})
	obj.set('statusCode', response.status_code)
	obj.set('statusMessage', response.status_msg)
	obj.set('headers', headers)
	obj.set('pipe', pipe_fn)
	headers.free()
	pipe_fn.free()
	return obj
}

fn install_http_like_module(ctx &Context, name string) {
	mut http_mod := ctx.js_module(name)
	get_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'url is required', name: 'TypeError'))
		}
		url := args[0].str()
		request := http_request_object(ctx)
		response := http.fetch(
			method:         .get
			url:            url
			allow_redirect: false
		) or {
			request.set('_vjsxPendingError', ctx.js_error(message: err.msg()))
			return request
		}
		if args.len > 1 && args[1].is_function() {
			response_obj := http_response_object(ctx, response, response.body.bytes())
			call_result := ctx.call_this(request, args[1], response_obj) or {
				request.set('_vjsxPendingError', ctx.js_error(message: err.msg()))
				response_obj.free()
				return request
			}
			call_result.free()
			response_obj.free()
		}
		return request
	})
	http_mod.export('get', get_fn)
	default_obj := ctx.js_object()
	default_obj.set('get', get_fn)
	http_mod.export_default(default_obj)
	http_mod.create()
	default_obj.free()
	get_fn.free()
}

pub fn (ctx &Context) install_http_module() {
	install_http_like_module(ctx, 'http')
}

pub fn (ctx &Context) install_https_module() {
	install_http_like_module(ctx, 'https')
}
