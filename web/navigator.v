module web

import vjsx { Context, Value }
import os
import runtime
import v.vmod

fn navigator_boot(ctx &Context, boot Value) {
	boot.set('get_navigator', ctx.js_function(fn [ctx] (args []Value) Value {
		uname := os.uname()
		manifest := vmod.from_file('${@VMODROOT}/v.mod') or { panic(err) }
		obj := ctx.js_object()
		obj.set('userAgent', '${manifest.name}/${manifest.version}')
		obj.set('platform', '${uname.sysname} ${uname.machine}')
		obj.set('hardwareConcurrency', runtime.nr_cpus())
		return obj
	}))
}

// Add Navigator API to globals.
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
//   web.navigator_api(ctx)
// }
// ```
pub fn navigator_api(ctx &Context) {
	glob, boot := get_bootstrap(ctx)
	navigator_boot(ctx, boot)
	ctx.eval_file('${@VMODROOT}/web/js/navigator.js', vjsx.type_module) or { panic(err) }
	glob.free()
}
