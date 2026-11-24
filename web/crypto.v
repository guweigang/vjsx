module web

import vjsx { Context, Value }

fn crypto_boot(ctx &Context, boot Value) {
	ctx.install_web_crypto_boot(boot)
}

// Add Crypto API to globals.
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
//   web.crypto_api(ctx)
// }
// ```
@[manualfree]
pub fn crypto_api(ctx &Context) {
	ctx.install_web_crypto_globals()
}
