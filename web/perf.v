module web

import vjsx { Context, Value }
import time

const offset = time.now().unix_nano()

fn performance_boot(ctx &Context, boot Value) {
	boot.set('perf_now', ctx.js_function(fn [ctx] (args []Value) Value {
		now := '${time.now().unix_nano() - web.offset}'
		return ctx.js_string('${now}')
	}))
}

// Add Performance API to globals.
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
//   web.performance_api(ctx)
// }
// ```
pub fn performance_api(ctx &Context) {
	glob, boot := get_bootstrap(ctx)
	performance_boot(ctx, boot)
	ctx.eval_runtime_file('web/js/perf.js', vjsx.type_module) or { panic(err) }
	glob.free()
}
