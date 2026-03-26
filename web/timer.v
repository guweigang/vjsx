module web

import vjsx { Context }

// Add timer API to globals (`setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`).
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.timer_api(ctx)
// }
// ```
pub fn timer_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/timer.js', vjsx.type_module) or { panic(err) }
}
