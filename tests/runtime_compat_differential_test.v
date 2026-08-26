import os
import runtimejs
import vjsx

fn test_node_runtime_contract_matches_node() {
	node := os.find_abs_path_of_executable('node') or {
		eprintln('skip differential runtime contract: node is not installed')
		return
	}
	node_result := os.execute('${node} ./tests/compat/runtime_contract_runner.mjs')
	assert node_result.exit_code == 0
	expected := node_result.output.trim_space()
	mut session := runtimejs.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['runtime_contract.mjs']
	})
	defer {
		session.close()
	}
	mut module_handle := session.import_module('./tests/compat/runtime_contract.mjs') or {
		panic(err)
	}
	defer {
		module_handle.close()
	}
	actual_value := module_handle.call_export('contractSnapshot') or { panic(err) }
	defer {
		actual_value.free()
	}
	assert actual_value.to_string() == expected
}
