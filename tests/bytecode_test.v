import vjsx

fn test_commonjs_bytecode_exports_and_persistent_instance() {
	source := '
class Parser {
  constructor() { this.calls = 0; }
  astify(sql) { this.calls++; return { sql, calls: this.calls }; }
}
module.exports = { Parser };
'
	bytecode := vjsx.compile_module(source,
		filename:        'parser.umd.js'
		runtime_profile: 'node'
	) or { panic(err) }
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		session.close()
	}
	ctx := session.context()
	mut module_handle := ctx.load_bytecode(bytecode) or { panic(err) }
	defer {
		module_handle.close()
	}
	assert module_handle.has_export('Parser')
	parser_class := module_handle.get('Parser') or { panic(err) }
	defer {
		parser_class.free()
	}
	parser := ctx.js_new_class(parser_class) or { panic(err) }
	defer {
		parser.free()
	}
	astify := parser.get('astify')
	defer {
		astify.free()
	}
	first := ctx.call_this(parser, astify, 'select 1') or { panic(err) }
	defer {
		first.free()
	}
	second := ctx.call_this(parser, astify, 'select 2') or { panic(err) }
	defer {
		second.free()
	}
	assert first.get('calls').to_int() == 1
	assert second.get('calls').to_int() == 2
}

fn test_bytecode_rejects_incompatible_profile_before_quickjs_load() {
	bytecode := vjsx.compile_module('module.exports = { value: 42 };',
		filename:        'value.js'
		runtime_profile: 'node'
	) or { panic(err) }
	mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{})
	defer {
		session.close()
	}
	session.context().load_bytecode(bytecode) or {
		assert err.msg().contains('incompatible runtime profile')
		return
	}
	assert false
}

fn test_bytecode_rejects_corruption_before_quickjs_load() {
	mut bytecode := vjsx.compile_module('module.exports = { value: 42 };',
		filename:        'value.js'
		runtime_profile: 'node'
	) or { panic(err) }
	bytecode[bytecode.len - 1] ^= 0xff
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		session.close()
	}
	session.context().load_bytecode(bytecode) or {
		assert err.msg().contains('checksum mismatch')
		return
	}
	assert false
}

fn test_bytecode_rejects_format_and_quickjs_abi_mismatches() {
	bytecode := vjsx.compile_module('module.exports = { value: 42 };',
		filename:        'value.js'
		runtime_profile: 'node'
	) or { panic(err) }
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		session.close()
	}
	mut bad_format := bytecode.clone()
	bad_format[8]++
	session.context().load_bytecode(bad_format) or {
		assert err.msg().contains('incompatible vjsx bytecode format')
		mut bad_abi := bytecode.clone()
		bad_abi[64] ^= 1
		session.context().load_bytecode(bad_abi) or {
			assert err.msg().contains('incompatible QuickJS ABI')
			return
		}
		assert false
		return
	}
	assert false
}
