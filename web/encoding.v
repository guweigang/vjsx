module web

import vjsx { Context, Value }

fn encoding_boot(ctx &Context, boot Value) {
	boot.set('text_encode', ctx.js_function_this(vjsx.host_text_encode))
	boot.set('text_decode', ctx.js_function_this(vjsx.host_text_decode))
	boot.set('decode_text', ctx.js_function_this(vjsx.host_decode_text))
	boot.set('text_encode_into', ctx.js_function_this(vjsx.host_text_encode_into))
}


// Add encoding API to globals (`TextEncoder`, `TextDecoder`).
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
//   web.encoding_api(ctx)
// }
// ```
@[manualfree]
pub fn encoding_api(ctx &Context) {
	glob, boot := get_bootstrap(ctx)
	encoding_boot(ctx, boot)
	ctx.eval_runtime_file('web/js/encoding.js', vjsx.type_module) or { panic(err) }
	glob.free()
}
