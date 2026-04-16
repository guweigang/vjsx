module web

import vjsx { Context }

// Add Blob API to globals.
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
//   web.blob_api(ctx)
// }
// ```
pub fn blob_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/blob.js', vjsx.type_module) or { panic(err) }
}
