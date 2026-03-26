module web

import vjsx { Context, Value }
import encoding.base64

// Btoa. this is return js_function value.
pub fn btoa(ctx &Context) Value {
	return ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw('args[0] is required')
		}
		ret := base64.encode_str(args[0].str())
		return ctx.js_string(ret)
	})
}

// Add btoa to globals.
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.btoa_api(ctx)
// }
// ```
@[manualfree]
pub fn btoa_api(ctx &Context) {
	glob := ctx.js_global()
	glob.set('btoa', btoa(ctx))
	glob.free()
}
