module vjsx

import crypto.rand
import os

fn fs_path_string(value Value) !string {
	path := value.utf8_string()!
	if path.contains('\x00') {
		return error('path must not contain null bytes')
	}
	return path
}

fn fs_dir_entries(ctx &Context, path string, with_types bool) !Value {
	names := os.ls(path)!
	entries := ctx.js_array()
	for name in names {
		if !with_types {
			entries.set(entries.len(), name)
			continue
		}
		target := os.join_path(path, name)
		if !fs_path_within_roots(target, ctx.capability_policy().fs_read_roots) {
			continue
		}
		st := os.lstat(target) or { continue }
		entry := stat_object(ctx, st, target)
		entry.set('name', name)
		entry.set('parentPath', path)
		entries.set(entries.len(), entry)
		entry.free()
	}
	return entries
}

fn (ctx &Context) fs_promise_extra_exports(roots []string) !Value {
	api := ctx.js_object()
	access := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'access requires a path string', 'ERR_INVALID_ARG_TYPE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		mut mode := 0
		if args.len > 1 && !args[1].is_undefined() {
			mode = args[1].to_int()
			if !args[1].is_number() || args[1].to_f64() != f64(mode) || mode !in 0 .. 8 {
				return promise.reject(fs_error(ctx, 'invalid access mode', 'ERR_INVALID_ARG_VALUE'))
			}
		}
		policy := ctx.capability_policy()
		candidates := if mode & 2 != 0 {
			target := writable_target_path(path, roots, policy) or {
				return promise.reject(fs_system_error(ctx, 'access', path, C.EACCES))
			}
			if mode & 5 != 0 && (!policy.allow_fs_read || !fs_path_within_roots(target, policy.fs_read_roots)) {
				return promise.reject(fs_system_error(ctx, 'access', path, C.EACCES))
			}
			[target]
		} else {
			readable_candidate_paths(path, roots, policy)
		}
		if candidates.len == 0 {
			return promise.reject(fs_system_error(ctx, 'access', path, C.EACCES))
		}
		mut status := C.ENOENT
		for target in candidates {
			status = $if windows {
				C.vjsx_file_access(target.to_wide(), mode)
			} $else {
				C.vjsx_file_access(&char(target.str), mode)
			}
			if status == 0 {
				return promise.resolve(ctx.js_undefined())
			}
			if status != C.ENOENT {
				break
			}
		}
		return promise.reject(fs_system_error(ctx, 'access', path, status))
	})
	append := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len < 2 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'appendFile requires a path and data', 'ERR_INVALID_ARG_TYPE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		target := writable_target_path(path, roots, ctx.capability_policy()) or {
			return promise.reject(fs_error(ctx, err.msg(), 'EACCES'))
		}
		bytes := if args[1].is_string() {
			text := args[1].utf8_string() or { return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE')) }
			text.bytes()
		} else {
			fs_value_to_bytes(args[1]) or { return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_TYPE')) }
		}
		mode := if args.len > 2 {
			fs_append_mode(args[2]) or {
				return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
			}
		} else {
			0o666
		}
		fs_write_bytes_mode(target, bytes, mode, false, true) or {
			return promise.reject(fs_error(ctx, err.msg(), 'EIO'))
		}
		return promise.resolve(ctx.js_undefined())
	})
	realpath := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'realpath requires a path string', 'ERR_INVALID_ARG_TYPE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		policy := ctx.capability_policy()
		candidates := readable_candidate_paths(path, roots, policy)
		if candidates.len == 0 {
			return promise.reject(fs_system_error(ctx, 'realpath', path, C.EACCES))
		}
		for candidate in candidates {
			if os.exists(candidate) {
				resolved := os.real_path(candidate)
				if !fs_path_within_roots(resolved, policy.fs_read_roots) {
					return promise.reject(fs_system_error(ctx, 'realpath', path, C.EACCES))
				}
				return promise.resolve(resolved)
			}
		}
		return promise.reject(fs_system_error(ctx, 'realpath', path, C.ENOENT))
	})
	mkdtemp := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'mkdtemp requires a path prefix', 'ERR_INVALID_ARG_TYPE'))
		}
		prefix := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		for _ in 0 .. 10 {
			bytes := rand.bytes(3) or { return promise.reject(fs_error(ctx, err.msg(), 'EIO')) }
			target := writable_target_path(prefix + bytes.hex(), roots, ctx.capability_policy()) or {
				return promise.reject(fs_error(ctx, err.msg(), 'EACCES'))
			}
			os.mkdir(target, mode: 0o700) or {
				if os.exists(target) {
					continue
				}
				return promise.reject(fs_error(ctx, err.msg(), 'EIO'))
			}
			return promise.resolve(target)
		}
		return promise.reject(fs_error(ctx, 'could not allocate a unique directory', 'EEXIST'))
	})
	dir_factory := ctx.eval('(entries, path) => {
		let position = 0, closed = false;
		return {
			path,
			async read() {
				if (closed) throw Object.assign(new Error("directory handle is closed"), { code: "ERR_DIR_CLOSED" });
				return entries[position++] ?? null;
			},
			async close() { closed = true; entries = []; }
		};
	}') or {
		api.free()
		return err
	}
	ctx.register_host_cleanup(fn [dir_factory] () { dir_factory.free() })
	opendir := ctx.js_function(fn [ctx, roots, dir_factory] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'opendir requires a path string', 'ERR_INVALID_ARG_TYPE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		policy := ctx.capability_policy()
		if readable_candidate_paths(path, roots, policy).len == 0 {
			return promise.reject(fs_system_error(ctx, 'opendir', path, C.EACCES))
		}
		target := resolve_existing_path(path, roots, policy) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ENOENT'))
		}
		if !os.is_dir(target) {
			return promise.reject(fs_system_error(ctx, 'opendir', path, C.ENOTDIR))
		}
		entries := fs_dir_entries(ctx, target, true) or {
			return promise.reject(fs_error(ctx, err.msg(), 'EIO'))
		}
		defer {
			entries.free()
		}
		dir := ctx.call(dir_factory, entries, target) or {
			return promise.reject(fs_error(ctx, err.msg(), 'EIO'))
		}
		return promise.resolve(dir)
	})
	open := ctx.fs_promise_open_export(roots)!
	api.set('access', access)
	api.set('appendFile', append)
	api.set('mkdtemp', mkdtemp)
	api.set('open', open)
	api.set('opendir', opendir)
	api.set('realpath', realpath)
	access.free()
	append.free()
	mkdtemp.free()
	open.free()
	opendir.free()
	realpath.free()
	return api
}

fn fs_append_mode(options Value) !int {
	if options.is_undefined() || options.is_null() {
		return 0o666
	}
	if options.is_string() {
		if options.str().to_lower() in ['utf8', 'utf-8'] {
			return 0o666
		}
		return error('unsupported appendFile encoding')
	}
	if !options.is_object() {
		return error('appendFile options must be a string or object')
	}
	encoding := string_option(options, 'encoding', 'utf8')!
	flag := string_option(options, 'flag', 'a')!
	if encoding.to_lower() !in ['utf8', 'utf-8'] || flag != 'a' {
		return error('unsupported appendFile options')
	}
	mode := options.get('mode')
	defer {
		mode.free()
	}
	if !mode.is_undefined() && !mode.is_null() && !mode.is_number() {
		return error('options.mode must be a number')
	}
	return if mode.is_number() { mode.to_int() } else { 0o666 }
}
