import os
import runtimejs
import vjsx

fn test_public_commonjs_detector_reads_without_resolving_or_executing() {
	root := os.join_path(os.temp_dir(), 'vjsx_commonjs_api_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	runtimejs.install_typescript_runtime(ctx) or { panic(err) }
	cases := [
		'module.exports = require("./missing-dependency.cjs"); globalThis.__detector_executed = true;',
		'exports.answer = 42;',
		'export const answer = 42;',
		'import { answer } from "./missing-dependency.mjs"; console.log(answer);',
		'globalThis.__detector_executed = true;',
	]
	for index, source in cases {
		path := os.join_path(root, 'case-${index}.js')
		os.write_file(path, source) or { panic(err) }
		assert runtimejs.is_commonjs_module(ctx, path) or { panic(err) } == (index < 2)
	}
	executed := ctx.js_global('__detector_executed')
	defer { executed.free() }
	assert executed.is_undefined()
}

fn test_public_commonjs_detector_installs_without_loading_typescript() ! {
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	assert runtimejs.is_commonjs_module(ctx, os.join_path(@VMODROOT, 'tests', 'cjs_runtime.cjs'))!
	detector := ctx.js_global('__vjs_is_commonjs')
	defer { detector.free() }
	assert detector.is_function()
	compiler := ctx.js_global('ts')
	defer { compiler.free() }
	assert compiler.is_undefined(), 'CommonJS detection must not load the TypeScript compiler'
	ready := ctx.js_global('__vjs_typescript_runtime_ready')
	defer { ready.free() }
	assert ready.is_undefined()
}

fn test_public_commonjs_detector_reports_unreadable_source() {
	root := os.join_path(os.temp_dir(), 'vjsx_commonjs_missing_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	missing := os.join_path(root, 'missing.cjs')
	if _ := runtimejs.is_commonjs_module(session.context(), missing) {
		assert false, 'expected source read error'
	} else {
		assert err.msg().contains('missing.cjs')
		assert err.msg() != 'CommonJS detector is not installed'
	}
}
