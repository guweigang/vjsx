import vjsx

fn main() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	array := ctx.js_array()

	array.call('push', 'foo')
	array.call('push', 'bar')
	array.call('unshift', 1)
	array.call('push', 2)

	assert array.len() == 4

	global := ctx.js_global()
	global.set('my_arr', array)

	value := ctx.eval('my_arr') or { panic(err) }
	ctx.end()

	assert ctx.json_stringify(value) == '[1,"foo","bar",2]'
	println('result => ${value}')

	value.free()
	global.free()
	array.free()
}
