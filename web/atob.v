module web

import vjsx { Context, Value }
import encoding.base64

// Atob. this is return js_function value.
pub fn atob(ctx &Context) Value {
	return ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw('args[0] is required')
		}
		ret := base64.decode_str(args[0].str())
		return ctx.js_string(ret)
	})
}

// Add atob to globals.
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
//   web.atob_api(ctx)
// }
// ```
@[manualfree]
pub fn atob_api(ctx &Context) {
	glob := ctx.js_global()
	glob.set('atob', atob(ctx))
	glob.free()
}
