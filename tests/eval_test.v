import vjsx

fn test_eval() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	value := ctx.eval('1 + 2') or { panic(err) }
	ctx.end()

	assert value.is_number() == true
	assert value.is_string() == false
	assert value.to_int() == 3

	value.free()
}

fn test_multi_eval() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	ctx.eval('const sum = (a, b) => a + b') or { panic(err) }
	ctx.eval('const mul = (a, b) => a * b') or { panic(err) }

	sum := ctx.eval('sum(${1}, ${2})') or { panic(err) }
	mul := ctx.eval('mul(${1}, ${2})') or { panic(err) }

	ctx.end()

	assert sum.to_int() == 3
	assert mul.to_int() == 2

	mul.free()
	sum.free()
}

fn test_eval_file() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	value := ctx.eval_file('./tests/test.js') or { panic(err) }
	ctx.end()

	assert value.is_string() == true
	assert value.to_string() == 'test foo'

	value.free()
}

fn test_string_key_and_json_helpers_keep_caller_owned_strings() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	obj := ctx.js_object()
	obj.set('name', 'vjsx')
	name := obj.get('name')
	parsed := ctx.json_parse('{"answer":42}')
	answer := parsed.get('answer')
	atom := ctx.new_atom('name')
	atom_value := obj.get(atom)

	assert name.to_string() == 'vjsx'
	assert answer.to_int() == 42
	assert atom_value.to_string() == 'vjsx'

	atom_value.free()
	atom.free()
	answer.free()
	parsed.free()
	name.free()
	obj.free()
}
