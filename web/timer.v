module web

import vjsx { Context }

// Add timer API to globals (`setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`).
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
//   web.timer_api(ctx)
// }
// ```
pub fn timer_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/timer.js', vjsx.type_module) or { panic(err) }
}
