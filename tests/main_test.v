import os
import v.vmod
import vjsx { Value }

fn test_runtime_version_matches_vmod() {
	vm := vmod.decode(@VMOD_FILE) or { panic(err) }
	assert vjsx.version == vm.version
}

fn test_host_policy_presets_are_explicit_and_compatible() {
	safe := vjsx.HostPolicy{}
	assert !safe.allow_env_read
	assert !safe.allow_env_write
	assert !safe.allow_subprocess
	assert !safe.allow_shell
	assert !safe.allow_fs_read
	assert !safe.allow_fs_write
	assert !safe.allow_network
	assert !safe.allow_process_chdir
	assert !safe.allow_process_exit
	assert vjsx.host_policy_safe() == safe

	trusted := vjsx.host_policy_trusted()
	assert trusted.allow_env_read
	assert trusted.allow_env_write
	assert trusted.allow_subprocess
	assert trusted.allow_shell
	assert trusted.allow_fs_read
	assert trusted.allow_fs_write
	assert trusted.allow_network
	assert trusted.allow_process_chdir
	assert trusted.allow_process_exit
	// Existing high-level configuration literals retain their historical
	// trusted behavior unless an embedder opts into the safe policy.
	assert vjsx.NodeCompatConfig{}.policy == trusted
	assert vjsx.NodeRuntimeConfig{}.policy == trusted
	assert vjsx.HostConfig{}.policy == trusted
	assert vjsx.ScriptRuntimeConfig{}.policy == trusted
}

fn test_node_policy_can_disable_process_env_writes() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	key := 'VJSX_POLICY_ENV_${os.getpid()}'
	ctx.install_node_compat(vjsx.NodeCompatConfig{
		console: false
		timers: false
		fs: false
		path: false
		os: false
		http: false
		https: false
		fetch: false
		child_process: false
		process: true
		sqlite: false
		mysql: false
		process_args: ['inline.js']
		policy: vjsx.HostPolicy{
			allow_env_write: false
		}
	})
	value := ctx.eval('process.env.${key} = "blocked"; String(process.env.${key} === undefined)') or {
		panic(err)
	}
	assert value.str() == 'true'
	value.free()
}

fn test_node_policy_can_disable_shell_execution() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	ctx.install_node_compat(vjsx.NodeCompatConfig{
		console: false
		timers: false
		fs: false
		path: false
		os: false
		http: false
		https: false
		fetch: false
		child_process: true
		process: false
		sqlite: false
		mysql: false
		policy: vjsx.HostPolicy{
			allow_subprocess: true
			allow_shell: false
		}
	})
	ctx.eval('
		import { execSync } from "child_process";
		try {
			execSync("printf should-not-run");
			globalThis.__shellPolicy = "ran";
		} catch (err) {
			globalThis.__shellPolicy = String(err.message);
		}
	', vjsx.type_module) or { panic(err) }
	global := ctx.js_global()
	value := global.get('__shellPolicy')
	assert value.str().contains('shell execution is disabled')
	value.free()
	global.free()
}

fn test_atom() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	atom_str := ctx.new_atom('foo')
	atom_int := ctx.new_atom(20)

	assert atom_str.str() == 'foo'
	assert atom_int.to_value().to_int() == 20

	obj := ctx.js_object()
	obj.set('foo', 'foo')
	obj.set('bar', 'bar')
	props := obj.property_names() or { panic(err) }
	for prop in props {
		assert prop.is_enumerable == true
	}
	assert props[0].atom.str() == 'foo'
	assert props[1].atom.str() == 'bar'
	obj.free()
	atom_int.free()
	atom_str.free()
}

fn test_callback() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	glob := ctx.js_global()
	glob.set('my_fn', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		return ctx.js_string(args.map(fn (val Value) string {
			if val.is_function() {
				return val.callback('baz').str()
			}
			return val.str()
		}).join(','))
	}))

	code := '
		my_fn("foo", "bar", (param) => {
			return param;
		})
	'

	value := ctx.eval(code) or { panic(err) }
	ctx.end()

	assert value.is_string() == true
	assert value.to_string() == 'foo,bar,baz'

	value.free()
	glob.free()
}

fn test_module() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	mut mod := ctx.js_module('my-module')
	mod.export('foo', ctx.js_function(fn [ctx] (args []Value) Value {
		assert args.len == 1
		assert args[0].str() == 'foo'
		return ctx.js_undefined()
	}))
	mod.export_default(mod.to_object())
	mod.create()

	code := '
		import mod, { foo } from "my-module";

		foo("foo");

		mod.foo("foo");
	'

	ctx.eval(code, vjsx.type_module) or { panic(err) }
	ctx.end()
}
