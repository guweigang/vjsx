module web

import vjsx { Context }

@[params]
pub struct BrowserHostConfig {
pub:
	asset_root  string
	window      bool = true
	dom         bool = true
	atob        bool = true
	btoa        bool = true
	console     bool = true
	navigator   bool = true
	crypto      bool = true
	encoding    bool = true
	performance bool = true
	timer       bool = true
	url         bool = true
	stream      bool = true
	blob        bool = true
	form_data   bool = true
	fetch       bool = true
	event       bool = true
}

// Full browser host preset.
pub fn browser_host_full() BrowserHostConfig {
	return BrowserHostConfig{}
}

// Minimal browser host preset.
// Keeps the common browser-like globals but skips heavier Web APIs.
pub fn browser_host_minimal() BrowserHostConfig {
	return BrowserHostConfig{
		dom:         false
		navigator:   false
		crypto:      false
		encoding:    false
		performance: false
		stream:      false
		blob:        false
		form_data:   false
		fetch:       false
		event:       false
	}
}

fn normalize_browser_host_config(config BrowserHostConfig) BrowserHostConfig {
	encoding := config.encoding || config.fetch
	stream := config.stream || encoding
	url := config.url || config.fetch
	blob := config.blob || config.fetch
	form_data := config.form_data || config.fetch
	return BrowserHostConfig{
		asset_root:  config.asset_root
		window:      config.window
		dom:         config.dom
		atob:        config.atob
		btoa:        config.btoa
		console:     config.console
		navigator:   config.navigator
		crypto:      config.crypto
		encoding:    encoding
		performance: config.performance
		timer:       config.timer
		url:         url
		stream:      stream
		blob:        blob
		form_data:   form_data
		fetch:       config.fetch
		event:       config.event
	}
}

fn eval_module_file(ctx &Context, path string) {
	ctx.eval_file(path, vjsx.type_module) or { panic(err) }
}

fn eval_runtime_module_file(ctx &Context, rel_path string) {
	ctx.eval_runtime_file(rel_path, vjsx.type_module) or { panic(err) }
}

fn get_bootstrap(ctx &Context) (vjsx.Value, vjsx.Value) {
	glob := ctx.js_global()
	if glob.get('__bootstrap').is_undefined() {
		glob.set('__bootstrap', ctx.js_object())
	}
	return glob, glob.get('__bootstrap')
}

// delete core `__bootstrap` from global
pub fn delete_bootstrap(ctx &Context) bool {
	glob := ctx.js_global()
	defer {
		glob.free()
	}
	if glob.get('__bootstrap').is_undefined() {
		return false
	}
	glob.delete('__bootstrap')
	return true
}

// Inject all browser host features.
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   mut session := vjsx.new_runtime_session()
//   defer {
//     session.close()
//   }
//   ctx := session.context()
//
//   web.inject_browser_host(ctx)
// }
// ```
pub fn inject_browser_host(ctx &Context, config BrowserHostConfig) {
	normalized := normalize_browser_host_config(config)
	if normalized.asset_root != '' {
		ctx.set_asset_root(normalized.asset_root)
	}
	if normalized.window {
		window_api(ctx)
	}
	if normalized.dom {
		dom_runtime_api(ctx)
	}
	if normalized.atob {
		atob_api(ctx)
	}
	if normalized.btoa {
		btoa_api(ctx)
	}
	glob, boot := get_bootstrap(ctx)
	if normalized.console || normalized.crypto || normalized.fetch {
		util_boot(ctx, boot)
	}
	if normalized.console {
		console_boot(ctx, boot)
	}
	if normalized.navigator {
		navigator_boot(ctx, boot)
	}
	if normalized.crypto {
		crypto_boot(ctx, boot)
	}
	if normalized.encoding {
		encoding_boot(ctx, boot)
	}
	if normalized.performance {
		performance_boot(ctx, boot)
	}
	if normalized.fetch {
		fetch_boot(ctx, boot)
	}
	if normalized.console {
		eval_runtime_module_file(ctx, 'web/js/console.js')
	}
	if normalized.performance {
		eval_runtime_module_file(ctx, 'web/js/perf.js')
	}
	if normalized.timer {
		eval_runtime_module_file(ctx, 'web/js/timer.js')
	}
	if normalized.stream {
		eval_runtime_module_file(ctx, 'web/js/stream.js')
	}
	if normalized.encoding {
		eval_runtime_module_file(ctx, 'web/js/encoding.js')
	}
	if normalized.url {
		eval_runtime_module_file(ctx, 'web/js/url.js')
		eval_runtime_module_file(ctx, 'web/js/url_pattern.js')
	}
	if normalized.crypto {
		eval_runtime_module_file(ctx, 'web/js/crypto.js')
	}
	if normalized.navigator {
		eval_runtime_module_file(ctx, 'web/js/navigator.js')
	}
	if normalized.blob {
		eval_runtime_module_file(ctx, 'web/js/blob.js')
	}
	if normalized.form_data {
		eval_runtime_module_file(ctx, 'web/js/form_data.js')
	}
	if normalized.fetch {
		eval_runtime_module_file(ctx, 'web/js/fetch.js')
	}
	if normalized.event {
		eval_runtime_module_file(ctx, 'web/js/event.js')
	}
	glob.delete('__bootstrap')
	glob.free()
}

// Inject the full browser runtime profile.
pub fn inject_browser_runtime(ctx &Context) {
	inject_browser_host(ctx, browser_host_full())
}

// Inject a smaller browser runtime profile.
pub fn inject_browser_runtime_minimal(ctx &Context) {
	inject_browser_host(ctx, browser_host_minimal())
}

// Inject all Web-API features.
pub fn inject(ctx &Context) {
	inject_browser_runtime(ctx)
}
