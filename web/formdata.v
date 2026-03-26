module web

import vjsx { Context }

// Add FormData API to globals.
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.formdata_api(ctx)
// }
// ```
pub fn formdata_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/form_data.js', vjsx.type_module) or { panic(err) }
}
