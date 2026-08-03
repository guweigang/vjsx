import os
import time
import vjsx

fn main() {
	if os.args.len < 2 {
		eprintln('usage: bytecode_parser_benchmark <parser.qbc> [sql]')
		exit(2)
	}
	path := os.args[1]
	query := if os.args.len > 2 {
		os.args[2]
	} else {
		'SELECT id, name FROM users WHERE id = 42'
	}

	read_started := time.now()
	bytecode := os.read_bytes(path) or { panic(err) }
	read_elapsed := time.since(read_started)

	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		session.close()
	}
	ctx := session.context()

	load_started := time.now()
	mut module_handle := ctx.load_bytecode(bytecode) or { panic(err) }
	load_elapsed := time.since(load_started)
	defer {
		module_handle.close()
	}

	parser_class := module_handle.get('Parser') or { panic(err) }
	defer {
		parser_class.free()
	}
	init_started := time.now()
	parser := ctx.js_new_class(parser_class) or { panic(err) }
	init_elapsed := time.since(init_started)
	defer {
		parser.free()
	}

	astify := parser.get('astify')
	defer {
		astify.free()
	}
	first_started := time.now()
	first := ctx.call_this(parser, astify, query) or { panic(err) }
	first_elapsed := time.since(first_started)
	first.free()

	mut last := ctx.js_undefined()
	repeat_started := time.now()
	for _ in 0 .. 100 {
		last.free()
		last = ctx.call_this(parser, astify, query) or { panic(err) }
	}
	repeat_elapsed := time.since(repeat_started)
	last.free()

	println('read_qbc: ${read_elapsed}')
	println('load_eval_bytecode: ${load_elapsed}')
	println('initialize_parser: ${init_elapsed}')
	println('first_astify: ${first_elapsed}')
	println('next_100_astify: ${repeat_elapsed}')
	println('next_astify_average: ${repeat_elapsed / 100}')
}
