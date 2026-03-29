import vjsx { Value }

fn test_atom() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	atom_str := ctx.new_atom('foo')
	atom_int := ctx.new_atom(20)

	assert atom_str.str() == 'foo'
	assert atom_int.to_value().to_int() == 20

	obj := ctx.js_object()
	obj.set('foo', 'foo')
	obj.set('bar', 'bar')
	props := obj.property_names() or { panic(err) }
	for prop in props {
		assert prop.is_enumerable == true
	}
	assert props[0].atom.str() == 'foo'
	assert props[1].atom.str() == 'bar'
	obj.free()
	atom_int.free()
	atom_str.free()
}

fn test_callback() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	glob := ctx.js_global()
	glob.set('my_fn', ctx.js_function(fn [ctx] (args []Value) Value {
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

	assert value.is_string() == true
	assert value.to_string() == 'foo,bar,baz'

	value.free()
	glob.free()
}

fn test_module() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	mut mod := ctx.js_module('my-module')
	mod.export('foo', ctx.js_function(fn [ctx] (args []Value) Value {
		assert args.len == 1
		assert args[0].str() == 'foo'
		return ctx.js_undefined()
	}))
	mod.export_default(mod.to_object())
	mod.create()

	code := '
		import mod, { foo } from "my-module";

		foo("foo");

		mod.foo("foo");
	'

	ctx.eval(code, vjsx.type_module) or { panic(err) }
	ctx.end()
}
