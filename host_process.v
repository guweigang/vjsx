module vjsx

import os

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

// Install a small `process` global with `cwd()` and `env`.
pub fn (ctx &Context) install_process(args []string) {
	global := ctx.js_global()
	process := ctx.js_object()
	process.set('cwd', ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(os.getwd())
	}))
	argv := ctx.js_array()
	for i, arg in args {
		argv.set(i, arg)
	}
	process.set('argv', argv)
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
	env.free()
	process.free()
	global.free()
}
