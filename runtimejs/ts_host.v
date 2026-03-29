module runtimejs

import os
import vjsx

const typescript_runtime_ready_key = '__vjs_typescript_runtime_ready'

fn install_typescript_host_bridge(ctx &vjsx.Context) {
	global := ctx.js_global()
	host := ctx.js_object()
	host.set('readFile', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		path := args[0].str()
		if !os.exists(path) || os.is_dir(path) {
			return ctx.js_undefined()
		}
		return ctx.js_string(os.read_file(path) or { return ctx.js_undefined() })
	}))
	host.set('fileExists', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		path := args[0].str()
		return ctx.js_bool(os.exists(path) && !os.is_dir(path))
	}))
	host.set('directoryExists', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(os.is_dir(args[0].str()))
	}))
	host.set('getDirectories', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_array()
		}
		path := args[0].str()
		mut arr := ctx.js_array()
		if os.is_dir(path) {
			entries := os.ls(path) or { []string{} }
			mut index := 0
			for entry in entries {
				full := os.join_path(path, entry)
				if os.is_dir(full) {
					arr.set(index, full)
					index++
				}
			}
		}
		return arr
	}))
	host.set('readDirectory', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_array()
		}
		root := args[0].str()
		mut arr := ctx.js_array()
		if !os.is_dir(root) {
			return arr
		}
		mut stack := [root]
		mut index := 0
		for stack.len > 0 {
			current := stack.pop()
			entries := os.ls(current) or { continue }
			for entry in entries {
				full := os.join_path(current, entry)
				if os.is_dir(full) {
					stack << full
				} else {
					arr.set(index, full)
					index++
				}
			}
		}
		return arr
	}))
	host.set('realpath', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			return ctx.js_string('')
		}
		path := args[0].str()
		if !os.exists(path) {
			return ctx.js_string(path)
		}
		return ctx.js_string(os.real_path(path))
	}))
	host.set('getCurrentDirectory', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_string(os.getwd())
	}))
	host.set('useCaseSensitiveFileNames', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		$if windows {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(true)
	}))
	global.set('__vjs_host', host)
	host.free()
	global.free()
}

fn typescript_runtime_is_installed(ctx &vjsx.Context) bool {
	ready := ctx.js_global(typescript_runtime_ready_key)
	defer {
		ready.free()
	}
	return !ready.is_undefined() && ready.to_bool()
}

fn mark_typescript_runtime_installed(ctx &vjsx.Context) {
	global := ctx.js_global()
	ready := ctx.js_bool(true)
	global.set(typescript_runtime_ready_key, ready)
	ready.free()
	global.free()
}

fn typescript_helper_path(name string) string {
	return os.join_path(@VMODROOT, 'thirdparty', 'typescript', 'lib', name)
}

fn install_typescript_helper(ctx &vjsx.Context, name string) ! {
	path := typescript_helper_path(name)
	if !os.exists(path) {
		return error('TypeScript helper not found: ${path}')
	}
	ctx.run_file(path) or { return error('failed to load TypeScript helper ${name}: ${err.msg()}') }
}

pub fn install_typescript_runtime(ctx &vjsx.Context) ! {
	if typescript_runtime_is_installed(ctx) {
		return
	}
	ts_path := typescript_runtime_path()
	if !os.exists(ts_path) {
		return error('TypeScript runtime not found: ${ts_path}')
	}
	install_typescript_host_bridge(ctx)
	ctx.run_file(ts_path) or { return error('failed to load TypeScript runtime: ${err.msg()}') }
	install_typescript_helper(ctx, 'vjs_ts_bootstrap.js')!
	install_typescript_helper(ctx, 'vjs_ts_scan.js')!
	install_typescript_helper(ctx, 'vjs_ts_commonjs.js')!
	install_typescript_helper(ctx, 'vjs_ts_resolver.js')!
	mark_typescript_runtime_installed(ctx)
}
