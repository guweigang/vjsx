module web

import vjsx { Context }

// Add Window API to globals. same as globalThis.
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
//   web.window_api(ctx)
// }
// ```
@[manualfree]
pub fn window_api(ctx &Context) {
	glob := ctx.js_global()
	glob.set('window', glob.dup_value())
	glob.set('self', glob.dup_value())
	glob.free()
}
