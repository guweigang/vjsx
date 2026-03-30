module vjsx

import os
import runtime

fn node_os_platform() string {
	return match os.user_os() {
		'macos' { 'darwin' }
		'windows' { 'win32' }
		else { os.user_os() }
	}
}

fn node_os_endianness() string {
	$if little_endian {
		return 'LE'
	} $else {
		return 'BE'
	}
}

fn node_os_uname() os.Uname {
	return os.uname()
}

fn node_os_arch() string {
	machine := node_os_uname().machine.to_lower()
	return match machine {
		'x86_64', 'amd64' {
			'x64'
		}
		'x86', 'i386', 'i686' {
			'ia32'
		}
		'aarch64', 'arm64' {
			'arm64'
		}
		'armv7l', 'armv7', 'armv6l', 'armv6' {
			'arm'
		}
		'ppc64le' {
			'ppc64'
		}
		else {
			if machine == '' {
				'unknown'
			} else {
				machine
			}
		}
	}
}

fn node_os_hostname() string {
	return os.hostname() or {
		host := os.getenv_opt('HOSTNAME') or { '' }
		if host != '' {
			return host
		}
		return os.getenv('COMPUTERNAME')
	}
}

fn node_os_username() string {
	name := os.loginname() or { '' }
	if name != '' {
		return name
	}
	for key in ['USER', 'USERNAME', 'LOGNAME'] {
		value := os.getenv_opt(key) or { '' }
		if value != '' {
			return value
		}
	}
	return 'unknown'
}

fn node_os_shell() string {
	for key in ['SHELL', 'ComSpec'] {
		value := os.getenv_opt(key) or { '' }
		if value != '' {
			return value
		}
	}
	return ''
}

fn node_os_cpus_value(ctx &Context) Value {
	mut arr := ctx.js_array()
	model := node_os_uname().machine
	for i in 0 .. runtime.nr_cpus() {
		mut cpu := ctx.js_object()
		mut times := ctx.js_object()
		times.set('user', ctx.js_int(0))
		times.set('nice', ctx.js_int(0))
		times.set('sys', ctx.js_int(0))
		times.set('idle', ctx.js_int(0))
		times.set('irq', ctx.js_int(0))
		cpu.set('model', ctx.js_string(if model == '' { node_os_arch() } else { model }))
		cpu.set('speed', ctx.js_int(0))
		cpu.set('times', times)
		arr.set(i, cpu)
		times.free()
		cpu.free()
	}
	return arr
}

fn node_os_loadavg_value(ctx &Context) Value {
	mut arr := ctx.js_array()
	arr.set(0, ctx.js_float(0.0))
	arr.set(1, ctx.js_float(0.0))
	arr.set(2, ctx.js_float(0.0))
	return arr
}

fn node_os_user_info_value(ctx &Context) Value {
	mut info := ctx.js_object()
	homedir := os.home_dir()
	shell := node_os_shell()
	info.set('username', ctx.js_string(node_os_username()))
	info.set('homedir', ctx.js_string(homedir))
	info.set('shell', ctx.js_string(shell))
	info.set('uid', ctx.js_int(-1))
	info.set('gid', ctx.js_int(-1))
	return info
}

// Install a Node-like `os` host module with common platform helpers.
pub fn (ctx &Context) install_os_module() {
	mut os_mod := ctx.js_module('os')
	eol := ctx.js_string('\n')
	dev_null := ctx.js_string(os.path_devnull)
	arch_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_arch())
	})
	platform_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_platform())
	})
	type_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		uname := node_os_uname()
		value := if uname.sysname == '' { node_os_platform() } else { uname.sysname }
		return ctx.js_string(value)
	})
	release_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_uname().release)
	})
	version_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_uname().version)
	})
	machine_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_uname().machine)
	})
	hostname_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_hostname())
	})
	homedir_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(os.home_dir())
	})
	tmpdir_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(os.temp_dir())
	})
	endianness_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_string(node_os_endianness())
	})
	available_parallelism_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.js_int(runtime.nr_cpus())
	})
	cpus_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return node_os_cpus_value(ctx)
	})
	totalmem_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		total := runtime.total_memory() or { usize(0) }
		return ctx.js_float(f64(total))
	})
	freemem_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		free_mem := runtime.free_memory() or { usize(0) }
		return ctx.js_float(f64(free_mem))
	})
	loadavg_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return node_os_loadavg_value(ctx)
	})
	user_info_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		return node_os_user_info_value(ctx)
	})
	os_mod.export('EOL', eol)
	os_mod.export('devNull', dev_null)
	os_mod.export('arch', arch_fn)
	os_mod.export('platform', platform_fn)
	os_mod.export('type', type_fn)
	os_mod.export('release', release_fn)
	os_mod.export('version', version_fn)
	os_mod.export('machine', machine_fn)
	os_mod.export('hostname', hostname_fn)
	os_mod.export('homedir', homedir_fn)
	os_mod.export('tmpdir', tmpdir_fn)
	os_mod.export('endianness', endianness_fn)
	os_mod.export('availableParallelism', available_parallelism_fn)
	os_mod.export('cpus', cpus_fn)
	os_mod.export('totalmem', totalmem_fn)
	os_mod.export('freemem', freemem_fn)
	os_mod.export('loadavg', loadavg_fn)
	os_mod.export('userInfo', user_info_fn)
	default_obj := ctx.js_object()
	default_obj.set('EOL', eol)
	default_obj.set('devNull', dev_null)
	default_obj.set('arch', arch_fn)
	default_obj.set('platform', platform_fn)
	default_obj.set('type', type_fn)
	default_obj.set('release', release_fn)
	default_obj.set('version', version_fn)
	default_obj.set('machine', machine_fn)
	default_obj.set('hostname', hostname_fn)
	default_obj.set('homedir', homedir_fn)
	default_obj.set('tmpdir', tmpdir_fn)
	default_obj.set('endianness', endianness_fn)
	default_obj.set('availableParallelism', available_parallelism_fn)
	default_obj.set('cpus', cpus_fn)
	default_obj.set('totalmem', totalmem_fn)
	default_obj.set('freemem', freemem_fn)
	default_obj.set('loadavg', loadavg_fn)
	default_obj.set('userInfo', user_info_fn)
	os_mod.export_default(default_obj)
	os_mod.create()
	default_obj.free()
	eol.free()
	dev_null.free()
	arch_fn.free()
	platform_fn.free()
	type_fn.free()
	release_fn.free()
	version_fn.free()
	machine_fn.free()
	hostname_fn.free()
	homedir_fn.free()
	tmpdir_fn.free()
	endianness_fn.free()
	available_parallelism_fn.free()
	cpus_fn.free()
	totalmem_fn.free()
	freemem_fn.free()
	loadavg_fn.free()
	user_info_fn.free()
}
