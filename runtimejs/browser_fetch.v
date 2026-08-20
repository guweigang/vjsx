module runtimejs

import vjsx

fn cli_browser_fetch_boot(ctx &vjsx.Context, boot vjsx.Value) {
	vjsx.install_fetch_core_boot(ctx, boot, vjsx.FetchGlobalsConfig{})
}
