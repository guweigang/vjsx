import vjsx

fn main() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	global := ctx.js_global()
	defer {
		global.free()
	}

	global.set('foo', 'bar')

	value := ctx.eval('foo') or { panic(err) }
	defer {
		value.free()
	}

	ctx.end()

	println('result => ${value}')
	// result => bar
}
