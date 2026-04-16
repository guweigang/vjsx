module web

import vjsx { Context }

// Add URL API to globals (`URL`, `URLSearchParams`).
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
//   web.url_api(ctx)
// }
// ```
pub fn url_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/url.js', vjsx.type_module) or { panic(err) }
	ctx.eval_runtime_file('web/js/url_pattern.js', vjsx.type_module) or { panic(err) }
}
