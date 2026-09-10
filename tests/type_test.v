import vjsx { Value }

fn test_type() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	obj := ctx.js_object()
	obj.set('foo', 'foo')
	assert obj.is_object() == true
	assert obj.get('foo').str() == 'foo'
	assert ctx.json_stringify(obj) == '{"foo":"foo"}'
	assert ctx.json_parse('{"foo":"foo"}').get('foo').str() == 'foo'

	arr := ctx.js_array()
	arr.call('push', 'foo')
	assert arr.is_array() == true
	assert arr.get(0).str() == 'foo'

	str := ctx.js_string('foo')
	assert str.str() == 'foo'

	numb := ctx.js_int(1)
	assert numb.to_int() == 1

	null := ctx.js_null()
	assert null.is_null() == true

	undefined := ctx.js_undefined()
	assert undefined.is_undefined() == true

	uninitialized := ctx.js_uninitialized()
	assert uninitialized.is_uninitialized() == true

	boolean := ctx.js_bool(true)
	assert boolean.is_bool() == true

	bigint := ctx.js_big_int(10000000000000)
	assert bigint.is_number() == false
	assert bigint.is_big_int() == true

	ctx.js_throw(ctx.js_error(message: 'error message'))
	assert ctx.js_exception().msg() == 'Error: error message\n'

	ctx.js_throw(ctx.js_type_error(message: 'error message'))
	assert ctx.js_exception().msg() == 'TypeError: error message\n'

	ctx.js_throw(ctx.js_error(message: 'error message', name: 'CustomError'))
	assert ctx.js_exception().msg() == 'CustomError: error message\n'

	arr_buf := ctx.js_array_buffer('foo'.bytes())
	assert arr_buf.instanceof('ArrayBuffer') == true
	empty_buf := ctx.js_array_buffer([]u8{})
	assert empty_buf.instanceof('ArrayBuffer') == true
	assert empty_buf.byte_len() == 0
	empty_buf.free()

	any_str := ctx.any_to_val('foo')
	assert any_str.str() == 'foo'

	cb := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_null()
	})
	assert cb.is_function() == true
}

fn test_call_this_releases_temporary_arguments_on_success_and_exception() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	echo := ctx.eval('(value) => ({ value })') or { panic(err) }
	thrower := ctx.eval('(value) => { throw new Error(value); }') or { panic(err) }
	defer {
		echo.free()
		thrower.free()
	}
	baseline := session.memory_usage()
	for i in 0 .. 250 {
		result := ctx.call_this(ctx.js_null(), echo, 'value-${i}') or { panic(err) }
		assert result.get('value').to_string() == 'value-${i}'
		result.free()
		ctx.call_this(ctx.js_null(), thrower, 'boom-${i}') or { continue }
		assert false, 'thrower should fail'
	}
	session.runtime().run_gc()
	after := session.memory_usage()
	assert after.object_count <= baseline.object_count + 8
	assert after.string_count <= baseline.string_count + 8
}

fn test_js_new_class_releases_temporary_arguments() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	class_value := ctx.eval('(class Box { constructor(value) { this.value = value; } })') or {
		panic(err)
	}
	defer {
		class_value.free()
	}
	baseline := session.memory_usage()
	for i in 0 .. 250 {
		instance := ctx.js_new_class(class_value, 'value-${i}') or { panic(err) }
		assert instance.get('value').to_string() == 'value-${i}'
		instance.free()
	}
	session.runtime().run_gc()
	after := session.memory_usage()
	assert after.object_count <= baseline.object_count + 4
	assert after.string_count <= baseline.string_count + 4
}

fn test_json_stringify_releases_temporary_values() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('({ value: "stable" })') or { panic(err) }
	defer {
		value.free()
	}
	baseline := session.memory_usage()
	for _ in 0 .. 250 {
		assert ctx.json_stringify_op(value, ctx.js_null(), '  ') == '{\n  "value": "stable"\n}'
	}
	session.runtime().run_gc()
	after := session.memory_usage()
	assert after.object_count <= baseline.object_count + 2
	assert after.string_count <= baseline.string_count + 2
}

fn test_call_this_captures_thrown_plain_object() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	thrower := ctx.eval('(function () { throw { name: "SyntaxError", message: "invalid SQL" }; })') or {
		panic(err)
	}
	defer {
		thrower.free()
	}

	ctx.call_this(ctx.js_null(), thrower) or {
		assert err.msg() == 'SyntaxError: invalid SQL\n'
		return
	}
	assert false, 'call_this should return the thrown object as an error'
}

fn test_call_this_captures_thrown_custom_error_like_class() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	thrower := ctx.eval('(function () { class ParserSyntaxError { constructor(message) { this.name = "SyntaxError"; this.message = message; } } throw new ParserSyntaxError("invalid SQL"); })') or {
		panic(err)
	}
	defer {
		thrower.free()
	}

	ctx.call_this(ctx.js_null(), thrower) or {
		assert err.msg() == 'SyntaxError: invalid SQL\n'
		return
	}
	assert false, 'call_this should return the custom error-like object as an error'
}

fn test_call_this_extracts_diagnostics_and_uses_to_string_fallback() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	thrower := ctx.eval('(function () { throw { name: "ParseError", stack: "parse stack", location: "query.sql:1", expected: "identifier", found: "FROM", toString() { return "parser failed"; } }; })') or {
		panic(err)
	}
	defer {
		thrower.free()
	}

	ctx.call_this(ctx.js_null(), thrower) or {
		assert err is vjsx.JSError
		if err is vjsx.JSError {
			assert err.name == 'ParseError'
			assert err.stack == 'parse stack'
			assert err.location == 'query.sql:1'
			assert err.expected == 'identifier'
			assert err.found == 'FROM'
		}
		assert err.msg() == 'parser failed\nparse stack'
		return
	}
	assert false, 'call_this should use the thrown value toString fallback'
}
