module runtimejs

import net.http { Method, Response, fetch, method_from_str, new_header, parse_multipart_form, post_multipart_form }
import os
import time
import vjsx

fn shell_quote(value string) string {
	return "'" + value.replace("'", "'\"'\"'") + "'"
}

fn curl_fetch(url string, method Method, header_map map[string]string, body string) !Response {
	_ := os.find_abs_path_of_executable('curl') or {
		return error('curl is not available')
	}
	stamp := '${os.getpid()}-${time.now().unix_micro()}'
	headers_path := os.join_path(os.temp_dir(), 'vjsx-curl-${stamp}.headers')
	body_path := os.join_path(os.temp_dir(), 'vjsx-curl-${stamp}.body')
	defer {
		os.rm(headers_path) or {}
		os.rm(body_path) or {}
	}
	mut parts := [
		'curl',
		'-sS',
		'-L',
		'--max-redirs',
		'16',
		'-D',
		shell_quote(headers_path),
		'-o',
		shell_quote(body_path),
		'-X',
		shell_quote(method.str()),
	]
	for key, value in header_map {
		parts << '-H'
		parts << shell_quote('${key}: ${value}')
	}
	if method !in [.get, .head] && body != '' {
		parts << '--data-binary'
		parts << shell_quote(body)
	}
	parts << shell_quote(url)
	result := os.execute(parts.join(' ') + ' 2>&1')
	if result.exit_code != 0 {
		mut message := result.output.trim_space()
		if message == '' {
			message = 'curl failed with exit code ${result.exit_code}'
		}
		return error(message)
	}
	headers_text := os.read_file(headers_path)!
	body_text := os.read_file(body_path)!
	return parse_curl_response(headers_text, body_text)
}

fn parse_curl_response(headers_text string, body_text string) !Response {
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
	mut header := new_header()
	for line in lines[1..] {
		raw := line.trim_space()
		if raw == '' || !raw.contains(':') {
			continue
		}
		key := raw.all_before(':').trim_space()
		value := raw.all_after(':').trim_space()
		header.add_custom(key, value) or {}
	}
	return Response{
		http_version: parts[0].all_after('/')
		status_code:  parts[1].int()
		status_msg:   status_msg
		header:       header
		body:         body_text
	}
}

fn cli_browser_fetch_boot(ctx &vjsx.Context, boot vjsx.Value) {
	boot.set('core_fetch', ctx.js_function_this(fn (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		mut error := this.ctx.js_undefined()
		promise := this.ctx.js_promise()
		url := args[0].str()
		opts := args[1]
		header := opts.get('headers')
		method := opts.get('method').str().to_lower()
		raw_body := opts.get('body')
		boundary := opts.get('boundary')
		mut hd := new_header()
		mut curl_headers := map[string]string{}
		mut user_agent := ''
		props := header.property_names() or { panic(err) }
		for data in props {
			key := data.atom.str()
			value := header.get(key).str()
			curl_headers[key] = value
			if key.to_lower() == 'user-agent' {
				user_agent = value
				hd.set(.user_agent, value)
				continue
			}
			hd.set_custom(key, value) or {
				error = this.ctx.js_error(message: err.msg())
				unsafe {
					goto reject
				}
				break
			}
		}
		mut body := raw_body.str()
		mut resp := Response{}
		request_method := method_from_str(method.to_upper())
		if boundary.is_undefined() {
			resp = fetch(
				method:     request_method
				url:        url
				header:     hd
				data:       body
				user_agent: user_agent
			) or {
				curl_fetch(url, request_method, curl_headers, body) or {
					error = this.ctx.js_error(message: err.msg())
					unsafe {
						goto reject
					}
					Response{}
				}
			}
		} else {
			form, files := parse_multipart_form(body, '----formdata-' + boundary.str())
			resp = post_multipart_form(url, form: form, header: hd, files: files) or {
				error = this.ctx.js_error(message: err.msg())
				unsafe {
					goto reject
				}
				Response{}
			}
		}
		mut resp_header := resp.header
		obj_header := this.ctx.js_object()
		for key in resp_header.keys() {
			val := resp_header.custom_values(key)
			obj_header.set(key, val.join('; '))
		}
		obj := this.ctx.js_object()
		obj.set('body', resp.body)
		obj.set('status', resp.status_code)
		obj.set('status_message', resp.status_msg)
		obj.set('header', obj_header)
		resp_header.free()
		return promise.resolve(obj)
		reject:
		return promise.reject(error)
	}))
}
