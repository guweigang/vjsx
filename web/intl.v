module web

import vjsx { Context, Value }

fn intl_boot(ctx &Context, boot Value) {
	boot.set('intl_date_time_parts', ctx.js_function_this(vjsx.host_intl_date_time_parts))
}

// Add a small Intl.DateTimeFormat API to globals.
@[manualfree]
pub fn intl_api(ctx &Context) {
	glob, boot := get_bootstrap(ctx)
	intl_boot(ctx, boot)
	ctx.eval_runtime_file('web/js/intl.js', vjsx.type_module) or { panic(err) }
	glob.free()
}
