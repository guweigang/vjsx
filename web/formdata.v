module web

import vjsx { Context }

// Add FormData API to globals.
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
//   web.formdata_api(ctx)
// }
// ```
pub fn formdata_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/form_data.js', vjsx.type_module) or { panic(err) }
}
