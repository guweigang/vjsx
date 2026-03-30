module vjsx

import os
import time

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

fn resolve_existing_path(path string, roots []string) !string {
	for candidate in candidate_paths(path, roots) {
		if os.exists(candidate) {
			return candidate
		}
	}
	return error('path not found: ${path}')
}

fn bool_option(value Value, key string, default_value bool) !bool {
	if value.is_undefined() || value.is_null() {
		return default_value
	}
	if !value.is_object() {
		return default_value
	}
	option := value.get(key)
	defer {
		option.free()
	}
	if option.is_undefined() || option.is_null() {
		return default_value
	}
	if !option.is_bool() {
		return error('options.${key} must be a boolean')
	}
	return option.to_bool()
}

fn string_option(value Value, key string, default_value string) !string {
	if value.is_undefined() || value.is_null() {
		return default_value
	}
	if !value.is_object() {
		return default_value
	}
	option := value.get(key)
	defer {
		option.free()
	}
	if option.is_undefined() || option.is_null() {
		return default_value
	}
	if !option.is_string() {
		return error('options.${key} must be a string')
	}
	return option.str()
}

fn temp_prefix_target(prefix string, roots []string) string {
	if os.is_abs_path(prefix) {
		return prefix
	}
	if prefix.contains(os.path_separator.str()) || prefix.contains('/') || prefix.contains('\\') {
		return write_target_path(prefix, roots)
	}
	return os.join_path(os.temp_dir(), prefix)
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

fn fs_value_to_bytes(value Value) ![]u8 {
	if value.is_string() {
		return value.str().bytes()
	}
	if value.is_object() && value.has('byteLength') {
		return value.to_bytes()
	}
	return error('write stream chunk must be a string or ArrayBuffer')
}

fn fs_append_bytes(path string, bytes []u8) ! {
	mut file := os.open_append(path)!
	defer {
		file.close()
	}
	file.write(bytes)!
}

fn fs_emit_finish(ctx &Context, stream Value) ! {
	finished_value := stream.get('_vjsxFinished')
	already_finished := finished_value.to_bool()
	finished_value.free()
	if already_finished {
		return
	}
	stream.set('_vjsxFinished', true)
	listeners := stream.get('_vjsxFinishListeners')
	defer {
		listeners.free()
	}
	for i in 0 .. listeners.len() {
		callback := listeners.get(i)
		if callback.is_function() {
			ctx.call_this(stream, callback) or {}
		}
		callback.free()
	}
}

fn fs_create_write_stream(ctx &Context, roots []string, path string) !Value {
	target := write_target_path(path, roots)
	os.write_file(target, '')!
	stream := ctx.js_object()
	finish_listeners := ctx.js_array()
	on_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len < 2 || !args[1].is_function() {
			return ctx.js_throw(ctx.js_error(
				message: 'event name and callback are required'
				name:    'TypeError'
			))
		}
		if args[0].str() != 'finish' {
			return this.dup_value()
		}
		listeners := this.get('_vjsxFinishListeners')
		listeners.set(listeners.len(), args[1])
		finished_value := this.get('_vjsxFinished')
		already_finished := finished_value.to_bool()
		finished_value.free()
		if already_finished {
			ctx.call_this(this, args[1]) or {}
		}
		listeners.free()
		return this.dup_value()
	})
	write_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'chunk is required', name: 'TypeError'))
		}
		closed_value := this.get('_vjsxClosed')
		is_closed := closed_value.to_bool()
		closed_value.free()
		if is_closed {
			return ctx.js_throw(ctx.js_error(message: 'write after close', name: 'Error'))
		}
		path_value := this.get('_vjsxPath')
		target := path_value.str()
		path_value.free()
		bytes := fs_value_to_bytes(args[0]) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		fs_append_bytes(target, bytes) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_bool(true)
	})
	close_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		this.set('_vjsxClosed', true)
		return ctx.js_undefined()
	})
	stream.set('_vjsxPath', target)
	stream.set('_vjsxClosed', false)
	stream.set('_vjsxFinished', false)
	stream.set('_vjsxFinishListeners', finish_listeners)
	stream.set('on', on_fn)
	stream.set('write', write_fn)
	stream.set('close', close_fn)
	finish_listeners.free()
	on_fn.free()
	write_fn.free()
	close_fn.free()
	return stream
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
			copy_err = ctx.js_error(
				message: 'source and destination are required'
				name:    'TypeError'
			)
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
	read_file_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		target := resolve_existing_path(args[0].str(), roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'Error'))
		}
		text := os.read_file(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_string(text)
	})
	write_file_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_throw(ctx.js_error(
				message: 'path and data are required'
				name:    'TypeError'
			))
		}
		target := write_target_path(args[0].str(), roots)
		os.write_file(target, args[1].str()) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		return ctx.js_undefined()
	})
	exists_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		for candidate in candidate_paths(args[0].str(), roots) {
			if os.exists(candidate) {
				return ctx.js_bool(true)
			}
		}
		return ctx.js_bool(false)
	})
	mkdir_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		recursive := if args.len > 1 {
			bool_option(args[1], 'recursive', false) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		} else {
			false
		}
		target := write_target_path(args[0].str(), roots)
		if recursive {
			os.mkdir_all(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		} else {
			os.mkdir(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		}
		return ctx.js_undefined()
	})
	mkdtemp_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'prefix is required', name: 'TypeError'))
		}
		base_prefix := temp_prefix_target(args[0].str(), roots)
		target := '${base_prefix}${os.getpid()}-${time.now().unix_micro()}'
		os.mkdir_all(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_string(target)
	})
	readdir_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		target := resolve_existing_path(args[0].str(), roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'Error'))
		}
		entries := os.ls(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		arr := ctx.js_array()
		for i, entry in entries {
			arr.set(i, entry)
		}
		return arr
	})
	rm_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		recursive := if args.len > 1 {
			bool_option(args[1], 'recursive', false) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		} else {
			false
		}
		force := if args.len > 1 {
			bool_option(args[1], 'force', false) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		} else {
			false
		}
		target := write_target_path(args[0].str(), roots)
		if recursive {
			os.rmdir_all(target) or {
				if force && !os.exists(target) {
					return ctx.js_undefined()
				}
				return ctx.js_throw(ctx.js_error(message: err.msg()))
			}
		} else {
			os.rm(target) or {
				if force && !os.exists(target) {
					return ctx.js_undefined()
				}
				return ctx.js_throw(ctx.js_error(message: err.msg()))
			}
		}
		return ctx.js_undefined()
	})
	stat_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		target := resolve_existing_path(args[0].str(), roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'Error'))
		}
		st := os.stat(target) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return stat_object(ctx, st, target)
	})
	copy_file_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_throw(ctx.js_error(
				message: 'source and destination are required'
				name:    'TypeError'
			))
		}
		src := resolve_existing_path(args[0].str(), roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'Error'))
		}
		dst := write_target_path(args[1].str(), roots)
		os.cp(src, dst) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_undefined()
	})
	chmod_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_throw(ctx.js_error(
				message: 'path and mode are required'
				name:    'TypeError'
			))
		}
		target := write_target_path(args[0].str(), roots)
		mode := if args[1].is_number() { args[1].to_int() } else { args[1].str().int() }
		os.chmod(target, mode) or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_undefined()
	})
	create_write_stream := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'path is required', name: 'TypeError'))
		}
		stream := fs_create_write_stream(ctx, roots, args[0].str()) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		return stream
	})
	rename_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut rename_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len < 2 {
			rename_err = ctx.js_error(
				message: 'source and destination are required'
				name:    'TypeError'
			)
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
	fs.export('readFileSync', read_file_sync)
	fs.export('writeFileSync', write_file_sync)
	fs.export('existsSync', exists_sync)
	fs.export('mkdirSync', mkdir_sync)
	fs.export('mkdtempSync', mkdtemp_sync)
	fs.export('readdirSync', readdir_sync)
	fs.export('rmSync', rm_sync)
	fs.export('statSync', stat_sync)
	fs.export('copyFileSync', copy_file_sync)
	fs.export('chmodSync', chmod_sync)
	fs.export('createWriteStream', create_write_stream)
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
	default_obj.set('readFileSync', read_file_sync)
	default_obj.set('writeFileSync', write_file_sync)
	default_obj.set('existsSync', exists_sync)
	default_obj.set('mkdirSync', mkdir_sync)
	default_obj.set('mkdtempSync', mkdtemp_sync)
	default_obj.set('readdirSync', readdir_sync)
	default_obj.set('rmSync', rm_sync)
	default_obj.set('statSync', stat_sync)
	default_obj.set('copyFileSync', copy_file_sync)
	default_obj.set('chmodSync', chmod_sync)
	default_obj.set('createWriteStream', create_write_stream)
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
	read_file_sync.free()
	write_file_sync.free()
	exists_sync.free()
	mkdir_sync.free()
	mkdtemp_sync.free()
	readdir_sync.free()
	rm_sync.free()
	stat_sync.free()
	copy_file_sync.free()
	chmod_sync.free()
	create_write_stream.free()
	rename_fn.free()
	read_json_fn.free()
	write_json_fn.free()
}
