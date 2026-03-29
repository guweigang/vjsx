import vjsx

fn main() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	code := '(() => {
		const fib = (n) => {
			return n < 1 ? 0
        : n <= 2 ? 1
        : fib(n - 1) + fib(n - 2)
		}
		return 2 * 1 + fib(10)
	})()'
	value := ctx.eval(code) or { panic(err) }
	ctx.end()

	println('Fib => ${value}')

	value.free()
}
