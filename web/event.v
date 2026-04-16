module web

import vjsx { Context }

// Add EventTarget API to globals
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
//   web.event_api(ctx)
// }
// ```
pub fn event_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/event.js', vjsx.type_module) or { panic(err) }
}
