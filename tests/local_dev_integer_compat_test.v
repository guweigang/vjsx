import vjsx

fn test_host_int_keeps_the_v_int_range_as_a_javascript_number() {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	// These boundaries exercise both QuickJS's immediate int and double storage.
	// Values remain in JavaScript's exact integer range; i64 still uses BigInt
	// through the separate js_big_int API.
	mut integers := [int(-2147483648), -1, 0, 2147483647]
	if sizeof(int) > 4 {
		integers << [int(-4294967296), int(2147483648), int(4294967296), int(9007199254740991)]
	}
	for integer in integers {
		value := ctx.js_int(integer)
		assert value.is_number()
		assert value.str() == integer.str()
		value.free()
		object := ctx.js_object()
		object.set('integer', integer)
		stored := object.get('integer')
		assert stored.is_number()
		assert stored.str() == integer.str()
		stored.free()
		object.free()
	}
}
