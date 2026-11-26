module vjsx

import os

#include "@VMODROOT/native/fs_file_handle.h"

struct C.VJSXFileStat {
	dev   u64
	ino   u64
	size  u64
	mode  u32
	mtime i64
	atime i64
	ctime i64
}

$if windows {
	fn C.vjsx_file_open(&u16, int, int) int
	fn C.vjsx_file_access(&u16, int) int
} $else {
	fn C.vjsx_file_open(&char, int, int) int
	fn C.vjsx_file_access(&char, int) int
}

fn C.vjsx_file_stat(int, &C.VJSXFileStat) int
fn C.vjsx_file_read(int, voidptr, int, i64) int
fn C.vjsx_file_truncate(int, i64) int
fn C.JS_GetTypedArrayBuffer(&C.JSContext, JSValueConst, &uint, &uint, &uint) C.JSValue

fn fs_errno_code(status int) string {
	return match status {
		C.ENOENT { 'ENOENT' }
		C.EACCES { 'EACCES' }
		C.EPERM { 'EPERM' }
		C.ENOTDIR { 'ENOTDIR' }
		C.EISDIR { 'EISDIR' }
		C.EINVAL { 'EINVAL' }
		C.EEXIST { 'EEXIST' }
		C.EBADF { 'EBADF' }
		C.ELOOP { 'ELOOP' }
		C.EMFILE { 'EMFILE' }
		C.ENOSPC { 'ENOSPC' }
		else { 'EIO' }
	}
}

fn fs_error(ctx &Context, message string, code string) Value {
	err := ctx.js_error(message: message)
	err.set('code', code)
	return err
}

fn fs_system_error(ctx &Context, operation string, path string, status int) Value {
	code := fs_errno_code(status)
	err := fs_error(ctx, '${operation} failed for ${path}: ${code}', code)
	err.set('path', path)
	err.set('syscall', operation)
	return err
}

fn fs_open_flags(value Value) !int {
	$if windows {
		if value.is_number() && value.to_f64() == f64(C._O_RDONLY) {
			return C._O_RDONLY
		}
		return match value.str() {
			'r' { C._O_RDONLY }
			'r+' { C._O_RDWR }
			'w' { C._O_WRONLY | C._O_CREAT | C._O_TRUNC }
			'wx' { C._O_WRONLY | C._O_CREAT | C._O_EXCL }
			'a' { C._O_WRONLY | C._O_CREAT | C._O_APPEND }
			else { error('unsupported open flags') }
		}
	} $else {
		if value.is_number() {
			flags := value.to_int()
			if value.to_f64() == f64(flags) && flags & ~(C.O_NONBLOCK | C.O_NOFOLLOW) == C.O_RDONLY {
				return flags
			}
			return error('unsupported numeric open flags')
		}
		return match value.str() {
			'r' { C.O_RDONLY }
			'r+' { C.O_RDWR }
			'w' { C.O_WRONLY | C.O_CREAT | C.O_TRUNC }
			'wx' { C.O_WRONLY | C.O_CREAT | C.O_EXCL }
			'a' { C.O_WRONLY | C.O_CREAT | C.O_APPEND }
			else { error('unsupported open flags') }
		}
	}
}

fn fs_constants(ctx &Context) Value {
	constants := ctx.js_object()
	constants.set('F_OK', 0)
	constants.set('X_OK', 1)
	constants.set('W_OK', 2)
	constants.set('R_OK', 4)
	$if windows {
		constants.set('O_RDONLY', int(C._O_RDONLY))
		constants.set('O_WRONLY', int(C._O_WRONLY))
		constants.set('O_RDWR', int(C._O_RDWR))
		constants.set('O_APPEND', int(C._O_APPEND))
		constants.set('O_CREAT', int(C._O_CREAT))
		constants.set('O_EXCL', int(C._O_EXCL))
		constants.set('O_TRUNC', int(C._O_TRUNC))
	} $else {
		constants.set('O_RDONLY', int(C.O_RDONLY))
		constants.set('O_WRONLY', int(C.O_WRONLY))
		constants.set('O_RDWR', int(C.O_RDWR))
		constants.set('O_APPEND', int(C.O_APPEND))
		constants.set('O_CREAT', int(C.O_CREAT))
		constants.set('O_EXCL', int(C.O_EXCL))
		constants.set('O_TRUNC', int(C.O_TRUNC))
		constants.set('O_NOFOLLOW', int(C.O_NOFOLLOW))
		constants.set('O_NONBLOCK', int(C.O_NONBLOCK))
	}
	return constants
}

struct FsPromiseFile {
	fd   int
	path string
}

@[heap]
struct FsPromiseFiles {
mut:
	files   map[int]FsPromiseFile
	next_id int = 1
}

fn fs_close_fd(fd int) {
	$if windows {
		C._close(fd)
	} $else {
		C.close(fd)
	}
}

fn (ctx &Context) fs_handle_read(file FsPromiseFile, args []Value) Value {
	mut bytes_offset := uint(0)
	mut bytes_length := uint(0)
	mut element_size := uint(0)
	buffer := ctx.c_val(C.JS_GetTypedArrayBuffer(ctx.ref, args[1].ref, &bytes_offset,
		&bytes_length, &element_size))
	if buffer.is_exception() {
		return buffer
	}
	defer {
		buffer.free()
	}
	mut size := uint(0)
	data := C.JS_GetArrayBuffer(ctx.ref, &size, buffer.ref)
	offset := uint(args[2].to_i64())
	length := args[3].to_u32()
	if uint(offset) > bytes_length || uint(length) > bytes_length - uint(offset) {
		return ctx.js_throw(fs_error(ctx, 'invalid file read range', 'EINVAL'))
	}
	if length == 0 {
		return ctx.js_int(0)
	}
	if data == unsafe { nil } || bytes_offset + uint(offset) + uint(length) > size {
		return ctx.js_throw(fs_error(ctx, 'invalid file read buffer', 'EINVAL'))
	}
	dest := unsafe { data + bytes_offset + uint(offset) }
	count := C.vjsx_file_read(file.fd, dest, int(length), args[4].to_i64())
	if count < 0 {
		return ctx.js_throw(fs_system_error(ctx, 'read', file.path, -count))
	}
	return ctx.js_int(count)
}

fn (ctx &Context) fs_promise_open_export(roots []string) !Value {
	mut state := &FsPromiseFiles{}
	ctx.register_host_cleanup(fn [mut state] () {
		for _, file in state.files {
			fs_close_fd(file.fd)
		}
		state.files.clear()
	})
	native := ctx.js_object()
	defer {
		native.free()
	}
	for method in ['close', 'stat', 'sync', 'truncate', 'read'] {
		function := ctx.js_function(fn [ctx, mut state, method] (args []Value) Value {
			id := args[0].to_int()
			file := state.files[id] or {
				if method == 'close' {
					return ctx.js_undefined()
				}
				return ctx.js_throw(fs_error(ctx, 'file handle is closed', 'EBADF'))
			}
			match method {
				'close' {
					state.files.delete(id)
					fs_close_fd(file.fd)
				}
				'stat' {
					mut st := C.VJSXFileStat{}
					status := C.vjsx_file_stat(file.fd, &st)
					if status != 0 {
						return ctx.js_throw(fs_system_error(ctx, 'fstat', file.path, status))
					}
					return stat_object(ctx, os.Stat{
						dev:   st.dev
						inode: st.ino
						size:  st.size
						mode:  st.mode
						mtime: st.mtime
						atime: st.atime
						ctime: st.ctime
					}, file.path)
				}
				'sync' {
					status := $if windows { C._commit(file.fd) } $else { C.fsync(file.fd) }
					if status != 0 {
						return ctx.js_throw(fs_error(ctx, 'fsync failed: ${file.path}', 'EIO'))
					}
				}
				'truncate' {
					status := C.vjsx_file_truncate(file.fd, args[1].to_i64())
					if status != 0 {
						return ctx.js_throw(fs_system_error(ctx, 'ftruncate', file.path, status))
					}
				}
				'read' {
					return ctx.fs_handle_read(file, args)
				}
				else {}
			}
			return ctx.js_undefined()
		})
		native.set(method, function)
		function.free()
	}
	factory := ctx.eval($embed_file('web/js/fs_file_handle.js').to_string())!
	defer {
		factory.free()
	}
	wrap := ctx.call(factory, native)!
	ctx.register_host_cleanup(fn [wrap] () { wrap.free() })
	return ctx.js_function(fn [ctx, roots, mut state, wrap] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(fs_error(ctx, 'open requires a path string', 'ERR_INVALID_ARG_TYPE'))
		}
		if state.files.len >= 128 {
			return promise.reject(fs_error(ctx, 'file handle limit reached', 'EMFILE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(fs_error(ctx, err.msg(), 'ERR_INVALID_ARG_VALUE'))
		}
		flags := if args.len < 2 || args[1].is_undefined() {
			0
		} else {
			fs_open_flags(args[1]) or { return promise.reject(fs_error(ctx, err.msg(), 'EINVAL')) }
		}
		writable := flags & 3 != 0
		readable := flags & 3 != 1
		policy := ctx.capability_policy()
		candidates := if writable {
			target := writable_target_path(path, roots, policy) or {
				return promise.reject(fs_error(ctx, err.msg(), 'EACCES'))
			}
			if readable && (!policy.allow_fs_read || !fs_path_within_roots(target, policy.fs_read_roots)) {
				return promise.reject(fs_system_error(ctx, 'open', path, C.EACCES))
			}
			[target]
		} else {
			readable_candidate_paths(path, roots, policy)
		}
		if candidates.len == 0 {
			return promise.reject(fs_system_error(ctx, 'open', path, C.EACCES))
		}
		mode := if args.len > 2 && args[2].is_number() { args[2].to_int() } else { 0o666 }
		mut status := C.ENOENT
		for target in candidates {
			fd := $if windows {
				C.vjsx_file_open(target.to_wide(), flags, mode)
			} $else {
				C.vjsx_file_open(&char(target.str), flags, mode)
			}
			if fd >= 0 {
				id := state.next_id
				state.next_id++
				state.files[id] = FsPromiseFile{ fd: fd, path: target }
				handle := ctx.call(wrap, id) or {
					state.files.delete(id)
					fs_close_fd(fd)
					return promise.reject(fs_error(ctx, err.msg(), 'EIO'))
				}
				return promise.resolve(handle)
			}
			status = -fd
			if status != C.ENOENT {
				break
			}
		}
		return promise.reject(fs_system_error(ctx, 'open', path, status))
	})
}
