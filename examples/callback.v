import vjsx { Value }

fn main() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	global := ctx.js_global()
	global.set('my_fn', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		return ctx.js_string(args.map(fn (val Value) string {
			if val.is_function() {
				return val.callback('baz').str()
			}
			return val.str()
		}).join(','))
	}))

	code := '
		my_fn("foo", "bar", (param) => {
			return param;
		})
	'

	value := ctx.eval(code) or { panic(err) }
	ctx.end()

	println('result => ${value}')

	value.free()
	global.free()
}
