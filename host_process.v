module vjsx

import os

const node_process_version = 'v0.0.0-vjsx'

fn process_env_proxy(ctx &Context) Value {
	return ctx.eval('(() => new Proxy(Object.create(null), {
		get(_target, prop) {
			if (typeof prop !== "string") {
				return undefined;
			}
			return globalThis.__vjs_process_env_get(prop);
		},
		has(_target, prop) {
			return typeof prop === "string" ? !!globalThis.__vjs_process_env_has(prop) : false;
		},
		set(_target, prop, value) {
			if (typeof prop !== "string") {
				return false;
			}
			globalThis.__vjs_process_env_set(prop, String(value));
			return true;
		},
		deleteProperty(_target, prop) {
			if (typeof prop !== "string") {
				return false;
			}
			globalThis.__vjs_process_env_unset(prop);
			return true;
		},
		ownKeys() {
			const keys = globalThis.__vjs_process_env_keys();
			return Array.isArray(keys) ? keys : [];
		},
		getOwnPropertyDescriptor(_target, prop) {
			if (typeof prop !== "string" || !globalThis.__vjs_process_env_has(prop)) {
				return undefined;
			}
			return {
				configurable: true,
				enumerable: true,
				value: globalThis.__vjs_process_env_get(prop),
				writable: true
			};
		}
	}))()') or {
		panic(err)
	}
}

fn process_stdio_value(ctx &Context, fd int, is_err bool) Value {
	mut stream := ctx.js_object()
	stream.set('fd', ctx.js_int(fd))
	stream.set('isTTY', ctx.js_bool(os.is_atty(fd) == 1))
	stream.set('write', ctx.js_function(fn [ctx, is_err] (args []Value) Value {
		if args.len > 0 {
			text := args[0].str()
			if is_err {
				eprint(text)
			} else {
				print(text)
			}
		}
		return ctx.js_bool(true)
	}))
	return stream
}

fn process_versions_value(ctx &Context) Value {
	mut versions := ctx.js_object()
	versions.set('node', ctx.js_string(node_process_version.trim_left('v')))
	versions.set('vjsx', ctx.js_string(node_process_version.trim_left('v')))
	versions.set('quickjs', ctx.js_string('embedded'))
	return versions
}

fn process_release_value(ctx &Context) Value {
	mut release := ctx.js_object()
	release.set('name', ctx.js_string('vjsx'))
	return release
}

// Install a Node-leaning `process` global with cwd/env/stdio helpers.
pub fn (ctx &Context) install_process(args []string) {
	global := ctx.js_global()
	process := ctx.js_object()
	process.set('cwd', ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(os.getwd())
	}))
	process.set('chdir', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		os.chdir(args[0].str()) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_undefined()
	}))
	argv := ctx.js_array()
	for i, arg in args {
		argv.set(i, arg)
	}
	exec_argv := ctx.js_array()
	process.set('platform', ctx.js_string(node_os_platform()))
	process.set('arch', ctx.js_string(node_os_arch()))
	process.set('pid', ctx.js_int(os.getpid()))
	process.set('ppid', ctx.js_int(os.getppid()))
	process.set('argv0', ctx.js_string(if args.len > 0 { args[0] } else { os.executable() }))
	process.set('execPath', ctx.js_string(os.executable()))
	process.set('version', ctx.js_string(node_process_version))
	versions := process_versions_value(ctx)
	process.set('versions', versions)
	release := process_release_value(ctx)
	process.set('release', release)
	process.set('title', ctx.js_string('vjsx'))
	process.set('exitCode', ctx.js_undefined())
	process.set('argv', argv)
	process.set('execArgv', exec_argv)
	process.set('stdin', process_stdio_value(ctx, 0, false))
	process.set('stdout', process_stdio_value(ctx, 1, false))
	process.set('stderr', process_stdio_value(ctx, 2, true))
	process.set('exit', ctx.js_function(fn [ctx] (args []Value) Value {
		mut code := 0
		if args.len > 0 && !args[0].is_undefined() && !args[0].is_null() {
			code = if args[0].is_number() { args[0].to_int() } else { args[0].str().int() }
		} else {
			proc := ctx.js_global('process')
			exit_code := proc.get('exitCode')
			if !exit_code.is_undefined() && !exit_code.is_null() {
				code = if exit_code.is_number() { exit_code.to_int() } else { exit_code.str().int() }
			}
			exit_code.free()
			proc.free()
		}
		exit(code)
		return ctx.js_undefined()
	}))
	global.set('__vjs_process_env_get', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		key := args[0].str()
		env := os.environ()
		if key !in env {
			return ctx.js_undefined()
		}
		return ctx.js_string(env[key])
	}))
	global.set('__vjs_process_env_has', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(args[0].str() in os.environ())
	}))
	global.set('__vjs_process_env_set', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_bool(false)
		}
		os.setenv(args[0].str(), args[1].str(), true)
		return ctx.js_bool(true)
	}))
	global.set('__vjs_process_env_unset', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		os.unsetenv(args[0].str())
		return ctx.js_bool(true)
	}))
	global.set('__vjs_process_env_keys', ctx.js_function(fn [ctx] (args []Value) Value {
		mut keys := os.environ().keys()
		keys.sort()
		arr := ctx.js_array()
		for i, key in keys {
			arr.set(i, key)
		}
		return arr
	}))
	env := process_env_proxy(ctx)
	process.set('env', env)
	global.set('process', process)
	argv.free()
	exec_argv.free()
	versions.free()
	release.free()
	env.free()
	process.free()
	global.free()
}
