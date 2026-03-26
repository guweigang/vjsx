module web

import vjsx { Context }

// Add EventTarget API to globals
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.event_api(ctx)
// }
// ```
pub fn event_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/event.js', vjsx.type_module) or { panic(err) }
}
