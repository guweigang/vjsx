module runtimejs

import vjsx

fn default_log(line string) {
	println(line)
}

fn default_error(line string) {
	eprintln(line)
}

@[params]
pub struct CliBrowserRuntimeConfig {
pub:
	repo_root string
	log_fn    vjsx.HostLogFn = default_log
	error_fn  vjsx.HostLogFn = default_error
}

fn cli_browser_bootstrap(ctx &vjsx.Context) (vjsx.Value, vjsx.Value) {
	glob := ctx.js_global()
	if glob.get('__bootstrap').is_undefined() {
		glob.set('__bootstrap', ctx.js_object())
	}
	return glob, glob.get('__bootstrap')
}

fn cli_browser_is_typed_array(this vjsx.Value, args []vjsx.Value) bool {
	val := args[0]
	buf := this.ctx.js_global('ArrayBuffer')
	call_is_view := buf.call('isView', val)
	is_view := call_is_view.to_bool()
	is_data_view := val.instanceof('DataView')
	return is_view && !is_data_view
}
