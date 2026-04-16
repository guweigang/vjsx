module web

import vjsx { Context }

// Add Stream API to globals (`ReadableStream`, `TransformStream`, `WritableStream`).
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
//   web.stream_api(ctx)
// }
// ```
pub fn stream_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/stream.js', vjsx.type_module) or { panic(err) }
}
