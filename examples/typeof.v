import vjsx

fn type_number() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	code := '(() => {
		return 1 + 2
	})()'
	val := ctx.eval(code) or { panic(err) }
	ctx.end()
	assert val.is_number() == true
	assert val.is_string() == false
	assert val.to_int() == 3
	assert val.to_string() == '3'
	assert val.typeof_name() == 'number'
	println('Number => ${val}')
	val.free()
}

fn type_bool() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	code := '(() => {
		return true
	})()'
	val := ctx.eval(code) or { panic(err) }
	ctx.end()
	assert val.is_bool() == true
	assert val.to_bool() == true
	assert val.typeof_name() == 'boolean'
	println('Bool => ${val}')
	val.free()
}

fn type_object() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	code := '(() => {
		return { name: "john" }
	})()'
	val := ctx.eval(code) or { panic(err) }
	ctx.end()
	json := ctx.json_stringify(val)
	assert val.is_object() == true
	assert json == '{"name":"john"}'
	assert val.typeof_name() == 'object'
	println('Object => ${json}')
	val.free()
}

fn type_array() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	code := '(() => {
		return [1, 2]
	})()'
	val := ctx.eval(code) or { panic(err) }
	ctx.end()
	json := ctx.json_stringify(val)
	assert val.is_array() == true
	assert json == '[1,2]'
	assert val.typeof_name() == 'object'
	println('Array => ${json}')
	val.free()
}

fn main() {
	type_number()
	type_bool()
	type_object()
	type_array()
}
