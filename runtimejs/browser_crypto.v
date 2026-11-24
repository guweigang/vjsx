module runtimejs

import vjsx

fn cli_browser_crypto_boot(ctx &vjsx.Context, boot vjsx.Value) {
	ctx.install_web_crypto_boot(boot)
}
