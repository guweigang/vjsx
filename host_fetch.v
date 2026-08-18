module vjsx

import net.http
import os
import time

@[params]
pub struct FetchGlobalsConfig {
pub:
	read_timeout        i64  = 30 * time.second
	write_timeout       i64  = 30 * time.second
	max_retries         int  = 5
	curl_proxy_fallback bool = true
}

const fetch_globals_config_key = '__vjs_fetch_globals_config'

struct FetchCoreRequest {
	url                 string
	method              http.Method
	header              http.Header
	body                string
	boundary            string
	read_timeout        i64
	write_timeout       i64
	max_retries         int
	curl_proxy_fallback bool
}

struct FetchCoreResult {
	response http.Response
	message  string
}

fn fetch_core_deadline(config FetchGlobalsConfig) i64 {
	mut deadline := config.read_timeout
	if config.write_timeout > deadline {
		deadline = config.write_timeout
	}
	if deadline <= 0 {
		deadline = 30 * time.second
	}
	return deadline + 250 * time.millisecond
}

fn fetch_core_run(request FetchCoreRequest) FetchCoreResult {
	if request.curl_proxy_fallback {
		curl_res := fetch_core_run_curl(request)
		if curl_res.message == '' {
			return curl_res
		}
	}
	mut resp := http.Response{}
	if request.boundary == '' {
		resp = http.fetch(
			url:           request.url
			method:        request.method
			header:        request.header
			data:          request.body
			read_timeout:  request.read_timeout
			write_timeout: request.write_timeout
			max_retries:   0
		) or {
			return FetchCoreResult{
				message: err.msg()
			}
		}
	} else {
		form, files := http.parse_multipart_form(request.body, '----formdata-' + request.boundary)
		resp = http.post_multipart_form(request.url,
			form:   form
			header: request.header
			files:  files
		) or { return FetchCoreResult{
			message: err.msg()
		} }
	}
	return FetchCoreResult{
		response: resp
	}
}

fn fetch_proxy_env() string {
	for key in ['https_proxy', 'HTTPS_PROXY', 'http_proxy', 'HTTP_PROXY', 'all_proxy', 'ALL_PROXY'] {
		value := os.getenv(key).trim_space()
		if value != '' {
			return value
		}
	}
	return ''
}

fn fetch_core_run_curl(request FetchCoreRequest) FetchCoreResult {
	curl_path := os.find_abs_path_of_executable('curl') or {
		return FetchCoreResult{
			message: 'curl is not available'
		}
	}
	stamp := '${os.getpid()}-${time.now().unix_micro()}'
	headers_path := os.join_path(os.temp_dir(), 'vjsx-fetch-${stamp}.headers')
	body_path := os.join_path(os.temp_dir(), 'vjsx-fetch-${stamp}.body')
	defer {
		os.rm(headers_path) or {}
		os.rm(body_path) or {}
	}
	mut args := [
		'-sS',
		'-L',
		'--max-redirs',
		'16',
		'--max-time',
		'${fetch_core_deadline_seconds(request)}',
		'-D',
		headers_path,
		'-o',
		body_path,
		'-X',
		request.method.str(),
	]
	if os.getenv('NODE_TLS_REJECT_UNAUTHORIZED') == '0' || os.getenv('VJS_FETCH_INSECURE') == '1' {
		args << '-k'
	}
	for key in request.header.keys() {
		values := request.header.custom_values(key)
		if values.len > 0 {
			args << '-H'
			args << '${key}: ${values.join('; ')}'
		}
	}
	if request.method !in [.get, .head] && request.body != '' {
		args << '--data-binary'
		args << request.body
	}
	args << '--'
	args << request.url
	mut proc := os.new_process(curl_path)
	proc.set_args(args)
	proc.set_redirect_stdio()
	proc.run()
	stdout := proc.stdout_slurp()
	stderr := proc.stderr_slurp()
	proc.wait()
	exit_code := proc.code
	proc.close()
	if exit_code != 0 {
		mut message := stderr.trim_space()
		if message == '' {
			message = stdout.trim_space()
		}
		if message == '' {
			message = 'curl failed with exit code ${exit_code}'
		}
		return FetchCoreResult{
			message: message
		}
	}
	headers_text := os.read_file(headers_path) or {
		return FetchCoreResult{
			message: err.msg()
		}
	}
	body_text := os.read_file(body_path) or { return FetchCoreResult{
		message: err.msg()
	} }
	resp := fetch_parse_curl_response(headers_text, body_text) or {
		return FetchCoreResult{
			message: err.msg()
		}
	}
	return FetchCoreResult{
		response: resp
	}
}

fn fetch_core_deadline_seconds(request FetchCoreRequest) int {
	mut deadline := request.read_timeout
	if request.write_timeout > deadline {
		deadline = request.write_timeout
	}
	if deadline <= 0 {
		deadline = 30 * time.second
	}
	seconds := int((deadline + time.second - 1) / time.second)
	if seconds <= 0 {
		return 30
	}
	return seconds
}

fn fetch_parse_curl_response(headers_text string, body_text string) !http.Response {
	normalized := headers_text.replace('\r\n', '\n')
	blocks := normalized.split('\n\n').filter(it.trim_space() != '')
	if blocks.len == 0 {
		return error('curl did not return response headers')
	}
	last := blocks[blocks.len - 1]
	mut lines := last.split('\n').filter(it.trim_space() != '')
	if lines.len == 0 {
		return error('curl returned an empty response header block')
	}
	status_line := lines[0].trim_space()
	parts := status_line.split_nth(' ', 3)
	if parts.len < 2 {
		return error('invalid curl status line: ${status_line}')
	}
	status_msg := if parts.len >= 3 { parts[2] } else { '' }
	mut header := http.new_header()
	for line in lines[1..] {
		raw := line.trim_space()
		if raw == '' || !raw.contains(':') {
			continue
		}
		key := raw.all_before(':').trim_space()
		value := raw.all_after(':').trim_space()
		header.add_custom(key, value) or {}
	}
	return http.Response{
		http_version: parts[0].all_after('/')
		status_code:  parts[1].int()
		status_msg:   status_msg
		header:       header
		body:         body_text
	}
}

fn fetch_core_run_with_deadline(request FetchCoreRequest, deadline i64) !http.Response {
	ch := chan FetchCoreResult{cap: 1}
	spawn fn [ch, request] () {
		ch <- fetch_core_run(request)
	}()
	mut output := FetchCoreResult{}
	select {
		result := <-ch {
			output = result
		}
		deadline * time.nanosecond {
			output = FetchCoreResult{
				message: 'fetch timed out after ${deadline / time.second} seconds'
			}
		}
	}
	if output.message != '' {
		return error(output.message)
	}
	return output.response
}

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

fn fetch_encoding_boot(ctx &Context, boot Value) {
	boot.set('text_encode', ctx.js_function_this(host_text_encode))
	boot.set('text_decode', ctx.js_function_this(host_text_decode))
	boot.set('decode_text', ctx.js_function_this(host_decode_text))
	boot.set('text_encode_into', ctx.js_function_this(host_text_encode_into))
}

fn fetch_config_from_boot(boot Value) FetchGlobalsConfig {
	value := boot.get(fetch_globals_config_key)
	defer {
		value.free()
	}
	if !value.is_object() {
		return FetchGlobalsConfig{}
	}
	read_timeout_value := value.get('readTimeout')
	defer {
		read_timeout_value.free()
	}
	write_timeout_value := value.get('writeTimeout')
	defer {
		write_timeout_value.free()
	}
	max_retries_value := value.get('maxRetries')
	defer {
		max_retries_value.free()
	}
	curl_proxy_fallback_value := value.get('curlProxyFallback')
	defer {
		curl_proxy_fallback_value.free()
	}
	read_timeout := if read_timeout_value.is_undefined() {
		i64(0)
	} else {
		i64(read_timeout_value.to_int())
	}
	write_timeout := if write_timeout_value.is_undefined() {
		i64(0)
	} else {
		i64(write_timeout_value.to_int())
	}
	max_retries := if max_retries_value.is_undefined() { -1 } else { max_retries_value.to_int() }
	return FetchGlobalsConfig{
		read_timeout:        if read_timeout > 0 { read_timeout } else { 30 * time.second }
		write_timeout:       if write_timeout > 0 { write_timeout } else { 30 * time.second }
		max_retries:         if max_retries >= 0 { max_retries } else { 5 }
		curl_proxy_fallback: if curl_proxy_fallback_value.is_undefined() {
			true
		} else {
			curl_proxy_fallback_value.to_bool()
		}
	}
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
	boot := this.ctx.js_global('__bootstrap')
	defer {
		boot.free()
	}
	fetch_config := fetch_config_from_boot(boot)
	resp := fetch_core_run_with_deadline(FetchCoreRequest{
		url:                 url
		method:              request_method
		header:              hd
		body:                body
		boundary:            if boundary.is_undefined() { '' } else { boundary.str() }
		read_timeout:        fetch_config.read_timeout
		write_timeout:       fetch_config.write_timeout
		max_retries:         fetch_config.max_retries
		curl_proxy_fallback: fetch_config.curl_proxy_fallback
	}, fetch_core_deadline(fetch_config)) or {
		error = this.ctx.js_error(message: err.msg())
		return promise.reject(error)
	}
	obj_header := this.ctx.js_object()
	for key in resp.header.keys() {
		vals := resp.header.custom_values(key)
		obj_header.set(key, vals.join('; '))
	}
	obj := this.ctx.js_object()
	arr_buf := this.ctx.js_array_buffer(resp.body.bytes())
	obj.set('body', arr_buf)
	arr_buf.free()
	obj.set('status', resp.status_code)
	obj.set('status_message', resp.status_msg)
	obj.set('header', obj_header)
	obj_header.free()
	return promise.resolve(obj)
}

fn fetch_boot(ctx &Context, boot Value) {
	boot.set('core_fetch', ctx.js_function_this(fetch_core))
}

pub fn (ctx &Context) install_fetch_globals(config FetchGlobalsConfig) {
	glob, boot := fetch_get_bootstrap(ctx)
	config_object := ctx.js_object()
	config_object.set('readTimeout', int(config.read_timeout))
	config_object.set('writeTimeout', int(config.write_timeout))
	config_object.set('maxRetries', config.max_retries)
	config_object.set('curlProxyFallback', config.curl_proxy_fallback)
	boot.set(fetch_globals_config_key, config_object)
	config_object.free()
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
