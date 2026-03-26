import vjsx

fn main() {
	rt := vjsx.new_runtime()
	defer {
		rt.free()
	}

	ctx := rt.new_context()
	defer {
		ctx.free()
	}

	value := ctx.run_file('./js/foo.js') or { panic(err) }
	defer {
		value.free()
	}

	println('result => ${value}')
}
