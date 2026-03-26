module web

import vjsx { Context }

// Add Blob API to globals.
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.blob_api(ctx)
// }
// ```
pub fn blob_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/blob.js', vjsx.type_module) or { panic(err) }
}
