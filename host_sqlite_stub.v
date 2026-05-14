module vjsx

$if !vjsx_sqlite ? {
	pub fn (ctx &Context) install_sqlite_module(roots []string) {
		_ = roots
		mut sqlite_mod := ctx.js_module('sqlite')
		open_fn := ctx.js_function(fn [ctx] (args []vjsx.Value) Value {
			_ = args
			promise := ctx.js_promise()
			return promise.reject(ctx.js_error(
				message: 'sqlite support is not built in; rerun with -d vjsx_sqlite'
				name:    'Error'
			))
		})
		sqlite_mod.export('open', open_fn)
		default_obj := ctx.js_object()
		default_obj.set('open', open_fn)
		sqlite_mod.export_default(default_obj)
		sqlite_mod.create()
		default_obj.free()
		open_fn.free()
	}
}
