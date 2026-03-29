import vjsx { Promise, Value }

fn test_promise() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	res := ctx.new_promise(fn (p Promise) Value {
		return p.resolve('foo')
	}).await()
	assert res.str() == 'foo'

	res2 := ctx.js_promise().resolve('bar').await()
	assert res2.str() == 'bar'
}
