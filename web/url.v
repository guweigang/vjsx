module web

import vjsx { Context }

// Add URL API to globals (`URL`, `URLSearchParams`).
// Example:
// ```v
// import vjsx
// import herudi.vjsx.web
//
// fn main() {
//   rt := vjsx.new_runtime()
//   ctx := rt.new_context()
//
//   web.url_api(ctx)
// }
// ```
pub fn url_api(ctx &Context) {
	ctx.eval_file('${@VMODROOT}/web/js/url.js', vjsx.type_module) or { panic(err) }
	ctx.eval_file('${@VMODROOT}/web/js/url_pattern.js', vjsx.type_module) or { panic(err) }
}
