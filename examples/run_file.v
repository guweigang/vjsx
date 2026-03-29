import vjsx

fn main() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	value := ctx.run_file('./js/foo.js') or { panic(err) }
	defer {
		value.free()
	}

	println('result => ${value}')
}
