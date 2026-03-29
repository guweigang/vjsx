module web

import vjsx { Context, Value }

fn console_boot(ctx &Context, boot Value) {
	boot.set('print', ctx.js_function(fn [ctx] (args []Value) Value {
		println(args.map(it.str()).join(' '))
		return ctx.js_undefined()
	}))
	boot.set('promise_state', ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.promise_state(args[0])
	}))
}

// Add console to globals.
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
//   web.console_api(ctx)
// }
// ```
@[manualfree]
pub fn console_api(ctx &Context) {
	create_util(ctx)
	glob, boot := get_bootstrap(ctx)
	console_boot(ctx, boot)
	ctx.eval_file('${@VMODROOT}/web/js/console.js', vjsx.type_module) or { panic(err) }
	glob.free()
}
