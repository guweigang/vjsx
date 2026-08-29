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
	curl_path           string
}

struct FetchCoreRequest {
	url                 string
	method              http.Method
	header              http.Header
	body                string
	body_is_binary      bool
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

@[heap]
struct FetchCoreConfigState {
	config FetchGlobalsConfig
}

@[heap]
struct FetchCurlTask {
mut:
	process           CurlProcess
	headers_path      string
	body_path         string
	output_path       string
	request_body_path string
	resolve           Value
	reject            Value
	settled           bool
	cleaned           bool
	cancelled         bool
	cancel_polls      int
}

fn fetch_core_run_native(request FetchCoreRequest) FetchCoreResult {
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
		) or { return FetchCoreResult{
			message: err.msg()
		} }
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

fn fetch_curl_paths() (string, string, string) {
	stamp := '${os.getpid()}-${time.now().unix_micro()}'
	headers_path := os.join_path(os.temp_dir(), 'vjsx-fetch-${stamp}.headers')
	body_path := os.join_path(os.temp_dir(), 'vjsx-fetch-${stamp}.body')
	output_path := os.join_path(os.temp_dir(), 'vjsx-fetch-${stamp}.output')
	return headers_path, body_path, output_path
}

fn fetch_curl_args(request FetchCoreRequest, headers_path string, body_path string, request_body_path string) []string {
	mut args := [
		'-q',
		'-sS',
		'--connect-timeout',
		'5',
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
		for val in values {
			args << '-H'
			args << '${key}: ${val}'
		}
	}
	if request.method !in [.get, .head] && request.body != '' {
		args << '--data-binary'
		args << if request.body_is_binary { '@${request_body_path}' } else { request.body }
	}
	args << '--'
	args << request.url
	return args
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

fn fetch_response_value(ctx &Context, response http.Response) Value {
	obj_header := ctx.js_object()
	for key in response.header.keys() {
		vals := response.header.custom_values(key)
		obj_header.set(key, vals.join('; '))
	}
	obj := ctx.js_object()
	arr_buf := ctx.js_array_buffer(response.body.bytes())
	obj.set('body', arr_buf)
	arr_buf.free()
	obj.set('status', response.status_code)
	obj.set('status_message', response.status_msg)
	obj.set('header', obj_header)
	obj_header.free()
	return obj
}

fn fetch_curl_task_cleanup(mut task FetchCurlTask) {
	if task.cleaned {
		return
	}
	task.cleaned = true
	os.rm(task.headers_path) or {}
	os.rm(task.body_path) or {}
	os.rm(task.output_path) or {}
	if task.request_body_path != '' {
		os.rm(task.request_body_path) or {}
	}
}

fn fetch_curl_task_stop(mut task FetchCurlTask) {
	if !task.process.done {
		task.process.terminate(true)
		task.process.reap()
	}
	fetch_curl_task_cleanup(mut task)
}

fn fetch_curl_task_settle(ctx Context, mut task FetchCurlTask, value Value, reject bool) {
	if task.settled {
		value.free()
		return
	}
	task.settled = true
	callback := if reject { task.reject } else { task.resolve }
	call_result := ctx.call(callback, value) or { ctx.js_undefined() }
	call_result.free()
	value.free()
	task.resolve.free()
	task.reject.free()
	for ctx.rt.is_job_pending() {
		ctx.rt.execute_pending_job() or { break }
	}
}

fn fetch_curl_task_finish(ctx Context, mut task FetchCurlTask) {
	defer {
		fetch_curl_task_cleanup(mut task)
	}
	if task.cancelled || task.settled {
		return
	}
	if task.process.exit_code != 0 {
		mut message := os.read_file(task.output_path) or { '' }
		message = message.trim_space()
		if message == '' {
			message = 'curl failed with exit code ${task.process.exit_code}'
		}
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(message: message), true)
		return
	}
	headers_text := os.read_file(task.headers_path) or {
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(message: err.msg()), true)
		return
	}
	body_text := os.read_file(task.body_path) or {
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(message: err.msg()), true)
		return
	}
	response := fetch_parse_curl_response(headers_text, body_text) or {
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(message: err.msg()), true)
		return
	}
	fetch_curl_task_settle(ctx, mut task, fetch_response_value(ctx, response), false)
}

fn fetch_curl_task_schedule(ctx Context, mut task FetchCurlTask) {
	timeout := ctx.js_global('setTimeout')
	if !timeout.is_function() {
		timeout.free()
		fetch_curl_task_stop(mut task)
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(
			message: 'curl transport requires setTimeout'
		), true)
		return
	}
	runner := ctx.js_function(fn [ctx, mut task] (args []Value) Value {
		finished := task.process.poll() or {
			fetch_curl_task_settle(ctx, mut task, ctx.js_error(message: err.msg()), true)
			fetch_curl_task_stop(mut task)
			return ctx.js_undefined()
		}
		if finished {
			fetch_curl_task_finish(ctx, mut task)
			return ctx.js_undefined()
		}
		if task.cancelled {
			task.cancel_polls++
			if task.cancel_polls >= 25 {
				task.process.terminate(true)
			}
		}
		fetch_curl_task_schedule(ctx, mut task)
		return ctx.js_undefined()
	})
	call_result := ctx.call(timeout, runner, 10) or { ctx.js_undefined() }
	call_result.free()
	runner.free()
	timeout.free()
}

fn fetch_start_curl(ctx Context, curl_path string, request FetchCoreRequest, resolve Value, reject Value) !Value {
	headers_path, body_path, output_path := fetch_curl_paths()
	request_body_path := if request.body_is_binary { output_path + '.request' } else { '' }
	if request_body_path != '' {
		os.write_file_array(request_body_path, request.body.bytes())!
		os.chmod(request_body_path, 0o600)!
	}
	args := fetch_curl_args(request, headers_path, body_path, request_body_path)
	process := start_curl_process(curl_path, args, output_path) or {
		os.rm(headers_path) or {}
		os.rm(body_path) or {}
		os.rm(output_path) or {}
		if request_body_path != '' {
			os.rm(request_body_path) or {}
		}
		return err
	}
	mut task := &FetchCurlTask{
		process:           process
		headers_path:      headers_path
		body_path:         body_path
		output_path:       output_path
		request_body_path: request_body_path
		resolve:           resolve.dup_value()
		reject:            reject.dup_value()
	}
	cancel := ctx.js_function(fn [ctx, mut task] (args []Value) Value {
		if task.cancelled || task.cleaned {
			return ctx.js_bool(false)
		}
		task.cancelled = true
		task.process.terminate(false)
		fetch_curl_task_settle(ctx, mut task, ctx.js_error(
			message: 'This operation was aborted'
			name:    'AbortError'
		), true)
		return ctx.js_bool(true)
	})
	ctx.register_host_cleanup(fn [mut task] () {
		if !task.cleaned {
			fetch_curl_task_stop(mut task)
		}
	})
	fetch_curl_task_schedule(ctx, mut task)
	return cancel
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

fn fetch_core_with_config(fetch_config FetchGlobalsConfig, this Value, args []Value) Value {
	ctx := this.ctx
	noop_cancel := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_bool(false)
	})
	if args.len < 4 || !args[2].is_function() || !args[3].is_function() {
		return ctx.js_throw('core_fetch requires resolve and reject callbacks')
	}
	resolve := args[2]
	reject := args[3]
	if args[0].is_undefined() || args[0].is_null() {
		error := ctx.js_error(message: 'url is required', name: 'TypeError')
		call_result := ctx.call(reject, error) or { ctx.js_undefined() }
		call_result.free()
		error.free()
		return noop_cancel
	}
	url := args[0].str()
	opts := if args.len > 1 { args[1].dup_value() } else { ctx.js_object() }
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
			error := ctx.js_error(message: err.msg())
			call_result := ctx.call(reject, error) or { ctx.js_undefined() }
			call_result.free()
			error.free()
			return noop_cancel
		}
		for data in props {
			key := data.atom.str()
			val := headers.get(key)
			hd.set_custom(key, val.str()) or {
				val.free()
				error := ctx.js_error(message: err.msg())
				call_result := ctx.call(reject, error) or { ctx.js_undefined() }
				call_result.free()
				error.free()
				return noop_cancel
			}
			val.free()
		}
	}
	request_method := http.Method.from(method.str().to_lower()) or { http.Method.get }
	mut body := ''
	mut body_is_binary := false
	if raw_body.instanceof('ArrayBuffer') || fetch_is_typed_array_bool(this, [raw_body]) {
		bytes := host_decode_text_bytes(this, raw_body) or {
			error := ctx.js_error(message: err.msg(), name: 'TypeError')
			call_result := ctx.call(reject, error) or { ctx.js_undefined() }
			call_result.free()
			error.free()
			return noop_cancel
		}
		body = bytes.bytestr()
		body_is_binary = true
	} else {
		body = raw_body.str()
	}
	request := FetchCoreRequest{
		url:                 url
		method:              request_method
		header:              hd
		body:                body
		body_is_binary:      body_is_binary
		boundary:            if boundary.is_undefined() { '' } else { boundary.str() }
		read_timeout:        fetch_config.read_timeout
		write_timeout:       fetch_config.write_timeout
		max_retries:         fetch_config.max_retries
		curl_proxy_fallback: fetch_config.curl_proxy_fallback
	}
	if request.curl_proxy_fallback && request.boundary == '' {
		curl_path := if fetch_config.curl_path != '' {
			fetch_config.curl_path
		} else {
			os.find_abs_path_of_executable('curl') or { '' }
		}
		if curl_path != '' {
			cancel := fetch_start_curl(ctx, curl_path, request, resolve, reject) or {
				error := ctx.js_error(message: err.msg())
				call_result := ctx.call(reject, error) or { ctx.js_undefined() }
				call_result.free()
				error.free()
				return noop_cancel
			}
			noop_cancel.free()
			return cancel
		}
	}
	result := fetch_core_run_native(request)
	if result.message != '' {
		error := ctx.js_error(message: result.message)
		call_result := ctx.call(reject, error) or { ctx.js_undefined() }
		call_result.free()
		error.free()
		return noop_cancel
	}
	response_value := fetch_response_value(ctx, result.response)
	call_result := ctx.call(resolve, response_value) or { ctx.js_undefined() }
	call_result.free()
	response_value.free()
	return noop_cancel
}

fn fetch_boot(ctx &Context, boot Value, config FetchGlobalsConfig) {
	state := &FetchCoreConfigState{
		config: config
	}
	boot.set('core_fetch', ctx.js_function_this(fn [state] (this Value, args []Value) Value {
		return fetch_core_with_config(state.config, this, args)
	}))
}

// Install the native fetch transport into an existing runtime bootstrap.
pub fn install_fetch_core_boot(ctx &Context, boot Value, config FetchGlobalsConfig) {
	fetch_boot(ctx, boot, config)
}

pub fn (ctx &Context) install_fetch_globals(config FetchGlobalsConfig) {
	glob, boot := fetch_get_bootstrap(ctx)
	install_fetch_core_boot(ctx, boot, config)
	fetch_util_boot(ctx, boot)
	fetch_encoding_boot(ctx, boot)
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
