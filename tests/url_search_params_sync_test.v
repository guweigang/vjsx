import os
import vjsx
import web

fn test_url_and_search_params_live_synchronization() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer { session.close() }
	assert_url_sync(session.context())
}

fn test_browser_profile_url_and_search_params_live_synchronization() {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	web.inject_browser_runtime(session.context())
	assert_url_sync(session.context())
}

fn assert_url_sync(ctx &vjsx.Context) {
	source := os.read_file(os.join_path(@VMODROOT, 'tests', 'url_search_params.mjs')) or {
		panic(err)
	}
	value := ctx.eval(source) or { panic(err) }
	value.free()
}
