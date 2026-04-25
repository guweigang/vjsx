module vjsx

// Install Node's promise-based timer module (`node:timers/promises`).
// The module uses the existing global timer wrapper, so QuickJS still owns the
// real timer queue while this layer only adds Node-compatible Promise semantics.
pub fn (ctx &Context) install_node_timers_promises_module() {
	ctx.eval_runtime_file('web/js/node_timers_promises.js', type_module) or { panic(err) }
	helpers := ctx.js_global('__vjsxNodeTimersPromises')
	set_timeout_fn := helpers.get('setTimeout')
	mut timers_mod := ctx.js_module('node:timers/promises')
	timers_mod.export('setTimeout', set_timeout_fn)
	default_obj := ctx.js_object()
	default_obj.set('setTimeout', set_timeout_fn)
	timers_mod.export_default(default_obj)
	timers_mod.create()
	default_obj.free()
	set_timeout_fn.free()
	helpers.free()
}
