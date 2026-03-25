module vjs

import os

// Console log sink used by the host helpers.
pub type HostLogFn = fn (line string)

@[params]
pub struct HostConfig {
pub:
	console  bool = true
	fs       bool = true
	path     bool = true
	process  bool = true
	fs_roots []string
	process_args []string
	log_fn   HostLogFn = default_host_log
	error_fn HostLogFn = default_host_error
}

fn default_host_log(line string) {
	println(line)
}

fn default_host_error(line string) {
	eprintln(line)
}

fn candidate_paths(path string, roots []string) []string {
	mut candidates := []string{}
	if os.is_abs_path(path) {
		candidates << path
		return candidates
	}
	candidates << path
	for root in roots {
		candidates << os.join_path(root, path)
	}
	return candidates
}

fn write_target_path(path string, roots []string) string {
	if os.is_abs_path(path) {
		return path
	}
	if roots.len > 0 {
		return os.join_path(roots[0], path)
	}
	return path
}

fn resolve_path(parts []string) string {
	if parts.len == 0 {
		return os.abs_path('')
	}
	mut current := ''
	for part in parts {
		if part == '' {
			continue
		}
		if os.is_abs_path(part) {
			current = part
			continue
		}
		if current == '' {
			current = os.abs_path(part)
		} else {
			current = os.join_path(current, part)
		}
	}
	if current == '' {
		return os.abs_path('')
	}
	return os.abs_path(current)
}

fn relative_path(from string, to string) string {
	from_abs := os.abs_path(from)
	to_abs := os.abs_path(to)
	sep := os.path_separator.str()
	from_parts := from_abs.split(sep).filter(it.len > 0)
	to_parts := to_abs.split(sep).filter(it.len > 0)
	mut common := 0
	for common < from_parts.len && common < to_parts.len && from_parts[common] == to_parts[common] {
		common++
	}
	mut parts := []string{}
	for _ in common .. from_parts.len {
		parts << '..'
	}
	for part in to_parts[common..] {
		parts << part
	}
	if parts.len == 0 {
		return '.'
	}
	return parts.join(sep)
}

fn stat_object(ctx &Context, st os.Stat, path string) Value {
	obj := ctx.js_object()
	obj.set('path', path)
	obj.set('size', int(st.size))
	obj.set('mtime', st.mtime)
	obj.set('ctime', st.ctime)
	obj.set('atime', st.atime)
	obj.set('isFile', ctx.js_function(fn [ctx, st] (args []Value) Value {
		return ctx.js_bool(st.get_filetype() == .regular)
	}))
	obj.set('isDirectory', ctx.js_function(fn [ctx, st] (args []Value) Value {
		return ctx.js_bool(st.get_filetype() == .directory)
	}))
	return obj
}

// Install a small reusable JS host into the current context.
pub fn (ctx &Context) install_host(config HostConfig) {
	if config.console {
		ctx.install_console(config.log_fn, config.error_fn)
	}
	if config.fs {
		ctx.install_fs_module(config.fs_roots)
	}
	if config.path {
		ctx.install_path_module()
	}
	if config.process {
		ctx.install_process(config.process_args)
	}
}

// Install `console.log(...)` and `console.error(...)`.
pub fn (ctx &Context) install_console(log_fn HostLogFn, error_fn HostLogFn) {
	global := ctx.js_global()
	console := ctx.js_object()
	console.set('log', ctx.js_function(fn [ctx, log_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		log_fn(line)
		return ctx.js_undefined()
	}))
	console.set('error', ctx.js_function(fn [ctx, error_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		error_fn(line)
		return ctx.js_undefined()
	}))
	console.set('warn', ctx.js_function(fn [ctx, error_fn] (args []Value) Value {
		line := args.map(it.to_string()).join(' ')
		error_fn(line)
		return ctx.js_undefined()
	}))
	global.set('console', console)
	console.free()
	global.free()
}

// Install a small `fs` host module with file and directory helpers.
pub fn (ctx &Context) install_fs_module(roots []string) {
	mut fs := ctx.js_module('fs')
	read_file := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut read_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			read_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		candidates := candidate_paths(path, roots)
		for candidate in candidates {
			if os.exists(candidate) {
				return promise.resolve(os.read_file(candidate) or {
					read_err = ctx.js_error(message: err.msg())
					unsafe {
						goto reject
					}
					''
				})
			}
		}
		read_err = ctx.js_error(message: 'file not found: ${path}', name: 'Error')
		reject:
		return promise.reject(read_err)
	})
	write_file := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut write_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len < 2 {
			write_err = ctx.js_error(message: 'path and data are required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		data := args[1].str()
		target := write_target_path(path, roots)
		os.write_file(target, data) or {
			write_err = ctx.js_error(message: err.msg())
			unsafe {
				goto reject
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(write_err)
	})
	exists_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut exists_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			exists_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		for candidate in candidate_paths(path, roots) {
			if os.exists(candidate) {
				return promise.resolve(true)
			}
		}
		return promise.resolve(false)
		reject:
		return promise.reject(exists_err)
	})
	mkdir_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut mkdir_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			mkdir_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		target := write_target_path(path, roots)
		os.mkdir_all(target) or {
			mkdir_err = ctx.js_error(message: err.msg())
			unsafe {
				goto reject
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(mkdir_err)
	})
	readdir_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut readdir_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			readdir_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		candidates := candidate_paths(path, roots)
		for candidate in candidates {
			if os.exists(candidate) && os.is_dir(candidate) {
				entries := os.ls(candidate) or {
					readdir_err = ctx.js_error(message: err.msg())
					unsafe {
						goto reject
					}
					[]string{}
				}
				arr := ctx.js_array()
				for i, entry in entries {
					arr.set(i, entry)
				}
				return promise.resolve(arr)
			}
		}
		readdir_err = ctx.js_error(message: 'directory not found: ${path}', name: 'Error')
		reject:
		return promise.reject(readdir_err)
	})
	rm_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut rm_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			rm_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		recursive := if args.len > 1 { args[1].to_bool() } else { false }
		target := write_target_path(path, roots)
		if recursive {
			os.rmdir_all(target) or {
				rm_err = ctx.js_error(message: err.msg())
				unsafe {
					goto reject
				}
			}
		} else {
			os.rm(target) or {
				rm_err = ctx.js_error(message: err.msg())
				unsafe {
					goto reject
				}
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(rm_err)
	})
	stat_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut stat_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			stat_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		for candidate in candidate_paths(path, roots) {
			if os.exists(candidate) {
				st := os.stat(candidate) or {
					stat_err = ctx.js_error(message: err.msg())
					unsafe {
						goto reject
					}
					os.Stat{}
				}
				return promise.resolve(stat_object(ctx, st, candidate))
			}
		}
		stat_err = ctx.js_error(message: 'path not found: ${path}', name: 'Error')
		reject:
		return promise.reject(stat_err)
	})
	copy_file_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut copy_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len < 2 {
			copy_err = ctx.js_error(message: 'source and destination are required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		src := args[0].str()
		dst := args[1].str()
		mut src_target := ''
		for candidate in candidate_paths(src, roots) {
			if os.exists(candidate) {
				src_target = candidate
				break
			}
		}
		if src_target == '' {
			copy_err = ctx.js_error(message: 'source not found: ${src}', name: 'Error')
			unsafe {
				goto reject
			}
		}
		dst_target := write_target_path(dst, roots)
		os.cp(src_target, dst_target) or {
			copy_err = ctx.js_error(message: err.msg())
			unsafe {
				goto reject
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(copy_err)
	})
	rename_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut rename_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len < 2 {
			rename_err = ctx.js_error(message: 'source and destination are required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		src := args[0].str()
		dst := args[1].str()
		mut src_target := ''
		for candidate in candidate_paths(src, roots) {
			if os.exists(candidate) {
				src_target = candidate
				break
			}
		}
		if src_target == '' {
			rename_err = ctx.js_error(message: 'source not found: ${src}', name: 'Error')
			unsafe {
				goto reject
			}
		}
		dst_target := write_target_path(dst, roots)
		os.mv(src_target, dst_target) or {
			rename_err = ctx.js_error(message: err.msg())
			unsafe {
				goto reject
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(rename_err)
	})
	read_json_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut read_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			read_err = ctx.js_error(message: 'path is required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		candidates := candidate_paths(path, roots)
		for candidate in candidates {
			if os.exists(candidate) {
				text := os.read_file(candidate) or {
					read_err = ctx.js_error(message: err.msg())
					unsafe {
						goto reject
					}
					''
				}
				return promise.resolve(ctx.json_parse(text))
			}
		}
		read_err = ctx.js_error(message: 'file not found: ${path}', name: 'Error')
		reject:
		return promise.reject(read_err)
	})
	write_json_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut write_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len < 2 {
			write_err = ctx.js_error(message: 'path and value are required', name: 'TypeError')
			unsafe {
				goto reject
			}
		}
		path := args[0].str()
		target := write_target_path(path, roots)
		data := args[1].json_stringify()
		os.write_file(target, data) or {
			write_err = ctx.js_error(message: err.msg())
			unsafe {
				goto reject
			}
		}
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(write_err)
	})
	fs.export('readFile', read_file)
	fs.export('writeFile', write_file)
	fs.export('exists', exists_fn)
	fs.export('mkdir', mkdir_fn)
	fs.export('readdir', readdir_fn)
	fs.export('rm', rm_fn)
	fs.export('stat', stat_fn)
	fs.export('copyFile', copy_file_fn)
	fs.export('rename', rename_fn)
	fs.export('readJson', read_json_fn)
	fs.export('writeJson', write_json_fn)
	default_obj := ctx.js_object()
	default_obj.set('readFile', read_file)
	default_obj.set('writeFile', write_file)
	default_obj.set('exists', exists_fn)
	default_obj.set('mkdir', mkdir_fn)
	default_obj.set('readdir', readdir_fn)
	default_obj.set('rm', rm_fn)
	default_obj.set('stat', stat_fn)
	default_obj.set('copyFile', copy_file_fn)
	default_obj.set('rename', rename_fn)
	default_obj.set('readJson', read_json_fn)
	default_obj.set('writeJson', write_json_fn)
	fs.export_default(default_obj)
	fs.create()
	default_obj.free()
	read_file.free()
	write_file.free()
	exists_fn.free()
	mkdir_fn.free()
	readdir_fn.free()
	rm_fn.free()
	stat_fn.free()
	copy_file_fn.free()
	rename_fn.free()
	read_json_fn.free()
	write_json_fn.free()
}

// Install a small `path` host module with path helpers.
pub fn (ctx &Context) install_path_module() {
	mut path_mod := ctx.js_module('path')
	join_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		parts := args.map(it.str())
		if parts.len == 0 {
			return ctx.js_string('')
		}
		mut joined := parts[0]
		for part in parts[1..] {
			joined = os.join_path(joined, part)
		}
		return ctx.js_string(joined)
	})
	dirname_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_string('')
		}
		return ctx.js_string(os.dir(args[0].str()))
	})
	basename_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_string('')
		}
		return ctx.js_string(os.base(args[0].str()))
	})
	extname_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_string('')
		}
		return ctx.js_string(os.file_ext(args[0].str()))
	})
	resolve_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		parts := args.map(it.str())
		return ctx.js_string(resolve_path(parts))
	})
	relative_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_string('')
		}
		return ctx.js_string(relative_path(args[0].str(), args[1].str()))
	})
	is_absolute_fn := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(os.is_abs_path(args[0].str()))
	})
	path_mod.export('join', join_fn)
	path_mod.export('dirname', dirname_fn)
	path_mod.export('basename', basename_fn)
	path_mod.export('extname', extname_fn)
	path_mod.export('resolve', resolve_fn)
	path_mod.export('relative', relative_fn)
	path_mod.export('isAbsolute', is_absolute_fn)
	default_obj := ctx.js_object()
	default_obj.set('join', join_fn)
	default_obj.set('dirname', dirname_fn)
	default_obj.set('basename', basename_fn)
	default_obj.set('extname', extname_fn)
	default_obj.set('resolve', resolve_fn)
	default_obj.set('relative', relative_fn)
	default_obj.set('isAbsolute', is_absolute_fn)
	path_mod.export_default(default_obj)
	path_mod.create()
	default_obj.free()
	join_fn.free()
	dirname_fn.free()
	basename_fn.free()
	extname_fn.free()
	resolve_fn.free()
	relative_fn.free()
	is_absolute_fn.free()
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
	env := ctx.js_object()
	for key, val in os.environ() {
		env.set(key, val)
	}
	process.set('env', env)
	global.set('process', process)
	argv.free()
	env.free()
	process.free()
	global.free()
}
