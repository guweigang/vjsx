module vjsx

import os

const runtime_asset_env_var = 'VJSX_ASSET_ROOT'
const runtime_asset_dev_root = @VMODROOT
const runtime_asset_abort_js = $embed_file('web/js/abort.js')
const runtime_asset_blob_js = $embed_file('web/js/blob.js')
const runtime_asset_buffer_js = $embed_file('web/js/buffer.js')
const runtime_asset_console_js = $embed_file('web/js/console.js')
const runtime_asset_crypto_js = $embed_file('web/js/crypto.js')
const runtime_asset_dom_runtime_js = $embed_file('web/js/dom_runtime.js')
const runtime_asset_encoding_js = $embed_file('web/js/encoding.js')
const runtime_asset_event_js = $embed_file('web/js/event.js')
const runtime_asset_fetch_js = $embed_file('web/js/fetch.js')
const runtime_asset_fetch_body_js = $embed_file('web/js/fetch/body.js')
const runtime_asset_fetch_headers_js = $embed_file('web/js/fetch/headers.js')
const runtime_asset_fetch_request_js = $embed_file('web/js/fetch/request.js')
const runtime_asset_fetch_response_js = $embed_file('web/js/fetch/response.js')
const runtime_asset_form_data_js = $embed_file('web/js/form_data.js')
const runtime_asset_inject_js = $embed_file('web/js/inject.js')
const runtime_asset_navigator_js = $embed_file('web/js/navigator.js')
const runtime_asset_node_timers_promises_js = $embed_file('web/js/node_timers_promises.js')
const runtime_asset_perf_js = $embed_file('web/js/perf.js')
const runtime_asset_polyfill_stream_js = $embed_file('web/js/polyfill/stream.js')
const runtime_asset_polyfill_url_pattern_js = $embed_file('web/js/polyfill/url_pattern.js')
const runtime_asset_stream_js = $embed_file('web/js/stream.js')
const runtime_asset_timer_js = $embed_file('web/js/timer.js')
const runtime_asset_url_js = $embed_file('web/js/url.js')
const runtime_asset_url_pattern_js = $embed_file('web/js/url_pattern.js')
const runtime_asset_util_js = $embed_file('web/js/util.js')

fn C.vjsx_js_value_to_module_def(C.JSValue) &C.JSModuleDef

pub fn (ctx &Context) set_asset_root(root string) {
	mut target := unsafe { ctx }
	target.asset_root = root.trim_space()
}

pub fn (ctx &Context) asset_root() string {
	if ctx.asset_root != '' {
		return ctx.asset_root
	}
	return os.getenv(runtime_asset_env_var).trim_space()
}

fn runtime_asset_error(rel_path string, root string) IError {
	if root == '' {
		return error('vjsx runtime asset not found: ${rel_path}; set ${runtime_asset_env_var} or ContextConfig.asset_root')
	}
	return error('vjsx runtime asset not found: ${rel_path}; resolved asset root: ${root}')
}

fn normalize_runtime_asset_path(rel_path string) !string {
	trimmed := rel_path.trim_space()
	if trimmed == '' {
		return error('vjsx runtime asset path is required')
	}
	return trimmed
}

fn runtime_embedded_asset_source(rel_path string) !string {
	return match rel_path {
		'web/js/abort.js' { runtime_asset_abort_js.to_string() }
		'web/js/blob.js' { runtime_asset_blob_js.to_string() }
		'web/js/buffer.js' { runtime_asset_buffer_js.to_string() }
		'web/js/console.js' { runtime_asset_console_js.to_string() }
		'web/js/crypto.js' { runtime_asset_crypto_js.to_string() }
		'web/js/dom_runtime.js' { runtime_asset_dom_runtime_js.to_string() }
		'web/js/encoding.js' { runtime_asset_encoding_js.to_string() }
		'web/js/event.js' { runtime_asset_event_js.to_string() }
		'web/js/fetch.js' { runtime_asset_fetch_js.to_string() }
		'web/js/fetch/body.js' { runtime_asset_fetch_body_js.to_string() }
		'web/js/fetch/headers.js' { runtime_asset_fetch_headers_js.to_string() }
		'web/js/fetch/request.js' { runtime_asset_fetch_request_js.to_string() }
		'web/js/fetch/response.js' { runtime_asset_fetch_response_js.to_string() }
		'web/js/form_data.js' { runtime_asset_form_data_js.to_string() }
		'web/js/inject.js' { runtime_asset_inject_js.to_string() }
		'web/js/navigator.js' { runtime_asset_navigator_js.to_string() }
		'web/js/node_timers_promises.js' { runtime_asset_node_timers_promises_js.to_string() }
		'web/js/perf.js' { runtime_asset_perf_js.to_string() }
		'web/js/polyfill/stream.js' { runtime_asset_polyfill_stream_js.to_string() }
		'web/js/polyfill/url_pattern.js' { runtime_asset_polyfill_url_pattern_js.to_string() }
		'web/js/stream.js' { runtime_asset_stream_js.to_string() }
		'web/js/timer.js' { runtime_asset_timer_js.to_string() }
		'web/js/url.js' { runtime_asset_url_js.to_string() }
		'web/js/url_pattern.js' { runtime_asset_url_pattern_js.to_string() }
		'web/js/util.js' { runtime_asset_util_js.to_string() }
		else { error('vjsx embedded runtime asset not found: ${rel_path}') }
	}
}

pub fn has_embedded_runtime_asset(rel_path string) bool {
	trimmed := rel_path.trim_space()
	if trimmed == '' {
		return false
	}
	runtime_embedded_asset_source(trimmed) or { return false }
	return true
}

fn (ctx &Context) resolve_runtime_asset_override_path(rel_path string) string {
	root := ctx.asset_root()
	if root == '' {
		return ''
	}
	candidate := os.join_path(root, rel_path)
	if os.exists(candidate) {
		return candidate
	}
	return ''
}

fn runtime_asset_module_name_to_rel_path(module_name string) string {
	mut name := module_name.trim_space()
	if name == '' {
		return ''
	}
	if name.starts_with('vjsx://') {
		name = name['vjsx://'.len..]
	}
	dev_prefix := os.join_path(runtime_asset_dev_root, 'web', 'js') + os.path_separator
	if name.starts_with(dev_prefix) {
		name = 'web/js/' + name[dev_prefix.len..]
	}
	if name.starts_with('web/js/') && has_embedded_runtime_asset(name) {
		return name
	}
	return ''
}

fn vjsx_runtime_module_loader(ctx &C.JSContext, module_name &char, opaque voidptr) &C.JSModuleDef {
	name := v_str(module_name)
	rel_path := runtime_asset_module_name_to_rel_path(name)
	if rel_path == '' {
		return C.vjsx_js_module_loader(ctx, module_name, opaque)
	}
	source := runtime_embedded_asset_source(rel_path) or {
		return C.vjsx_js_module_loader(ctx, module_name, opaque)
	}
	source_path := os.join_path(runtime_asset_dev_root, rel_path)
	ref := C.JS_Eval(ctx, source.str, usize(source.len), source_path.str, type_module | type_compile_only)
	if C.JS_IsException(ref) == 1 {
		return unsafe { nil }
	}
	C.js_module_set_import_meta(ctx, ref, true, true)
	return C.vjsx_js_value_to_module_def(ref)
}

pub fn (ctx &Context) resolve_runtime_asset_path(rel_path string) !string {
	trimmed := normalize_runtime_asset_path(rel_path)!
	mut roots := []string{}
	root := ctx.asset_root()
	if root != '' {
		roots << root
	}
	if runtime_asset_dev_root !in roots {
		roots << runtime_asset_dev_root
	}
	for candidate_root in roots {
		candidate := os.join_path(candidate_root, trimmed)
		if os.exists(candidate) {
			return candidate
		}
	}
	return runtime_asset_error(trimmed, if root != '' { root } else { runtime_asset_dev_root })
}

@[manualfree]
fn (ctx &Context) eval_runtime_source_custom_meta(source string, fname string, flag int, set_meta SetMeta) !Value {
	return ctx.js_eval_core(
		input:    source.str
		len:      usize(source.len)
		fname:    fname.str
		flag:     flag
		set_meta: set_meta
	)!
}

@[manualfree]
pub fn (ctx &Context) eval_runtime_file(rel_path string, args ...EvalArgs) !Value {
	flag := if args.len == 1 { args[0] as int } else { type_global }
	trimmed := normalize_runtime_asset_path(rel_path)!
	override_path := ctx.resolve_runtime_asset_override_path(trimmed)
	if override_path != '' {
		return ctx.eval_file_custom_meta(override_path, flag, def_set_meta)
	}
	source := runtime_embedded_asset_source(trimmed) or {
		path := ctx.resolve_runtime_asset_path(trimmed)!
		return ctx.eval_file_custom_meta(path, flag, def_set_meta)
	}
	path := os.join_path(runtime_asset_dev_root, trimmed)
	return ctx.eval_runtime_source_custom_meta(source, path, flag, def_set_meta)
}

pub fn embedded_runtime_asset_source(rel_path string) !string {
	trimmed := normalize_runtime_asset_path(rel_path)!
	return runtime_embedded_asset_source(trimmed)!
}

pub fn embedded_runtime_asset_paths() []string {
	return [
		'web/js/abort.js',
		'web/js/blob.js',
		'web/js/buffer.js',
		'web/js/console.js',
		'web/js/crypto.js',
		'web/js/dom_runtime.js',
		'web/js/encoding.js',
		'web/js/event.js',
		'web/js/fetch.js',
		'web/js/fetch/body.js',
		'web/js/fetch/headers.js',
		'web/js/fetch/request.js',
		'web/js/fetch/response.js',
		'web/js/form_data.js',
		'web/js/inject.js',
		'web/js/navigator.js',
		'web/js/node_timers_promises.js',
		'web/js/perf.js',
		'web/js/polyfill/stream.js',
		'web/js/polyfill/url_pattern.js',
		'web/js/stream.js',
		'web/js/timer.js',
		'web/js/url.js',
		'web/js/url_pattern.js',
		'web/js/util.js',
	]
}
