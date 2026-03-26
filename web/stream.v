module web

import vjsx { Context }

// Add Stream API to globals (`ReadableStream`, `TransformStream`, `WritableStream`).
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.stream_api(ctx)
// }
// ```
pub fn stream_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/stream.js', vjsx.type_module) or { panic(err) }
}
