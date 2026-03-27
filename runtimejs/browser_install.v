module runtimejs

import os
import vjsx

pub fn install_cli_browser_runtime(ctx &vjsx.Context, config CliBrowserRuntimeConfig) {
	ctx.install_console(config.log_fn, config.error_fn)
	ctx.install_binary_globals()
	ctx.install_timer_globals()
	ctx.install_url_globals()
	global := ctx.js_global()
	global.set('window', global.dup_value())
	global.set('self', global.dup_value())
	global.free()
	glob, boot := cli_browser_bootstrap(ctx)
	cli_browser_util_boot(ctx, boot)
	cli_browser_crypto_boot(ctx, boot)
	cli_browser_encoding_boot(ctx, boot)
	cli_browser_fetch_boot(ctx, boot)
	glob.free()
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'crypto.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'stream.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'encoding.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'blob.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'form_data.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'event.js'), vjsx.type_module) or {
		panic(err)
	}
	ctx.eval_file(os.join_path(config.repo_root, 'web', 'js', 'fetch.js'), vjsx.type_module) or {
		panic(err)
	}
}
