module runtimejs

import vjsx

pub fn try_install_cli_browser_runtime(ctx &vjsx.Context, config CliBrowserRuntimeConfig) ! {
	ctx.set_runtime_profile('browser')
	ctx.install_console(config.log_fn, config.error_fn)
	ctx.try_install_binary_globals()!
	ctx.try_install_timer_globals()!
	ctx.try_install_url_globals()!
	global := ctx.js_global()
	global.set('window', global.dup_value())
	global.set('self', global.dup_value())
	global.free()
	glob, boot := cli_browser_bootstrap(ctx)
	defer {
		glob.delete('__bootstrap')
		boot.free()
		glob.free()
	}
	cli_browser_util_boot(ctx, boot)
	cli_browser_crypto_boot(ctx, boot)
	cli_browser_encoding_boot(ctx, boot)
	cli_browser_intl_boot(ctx, boot)
	cli_browser_fetch_boot(ctx, boot)
	for asset in ['web/js/crypto.js', 'web/js/stream.js', 'web/js/encoding.js', 'web/js/intl.js',
		'web/js/blob.js', 'web/js/form_data.js', 'web/js/event.js', 'web/js/abort.js',
		'web/js/fetch.js'] {
		value := ctx.eval_runtime_file(asset, vjsx.type_module)!
		value.free()
	}
}

// Compatibility wrapper for callers that relied on panic-on-install-failure.
pub fn install_cli_browser_runtime(ctx &vjsx.Context, config CliBrowserRuntimeConfig) {
	try_install_cli_browser_runtime(ctx, config) or { panic(err) }
}
