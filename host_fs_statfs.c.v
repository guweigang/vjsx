module vjsx

$if windows {
	import os
}

#include "@VMODROOT/native/fs_statfs.h"

struct C.VJSXStatFs {
	fs_type u64
	bsize   u64
	frsize  u64
	blocks  u64
	bfree   u64
	bavail  u64
	files   u64
	ffree   u64
}

$if windows {
	fn C.vjsx_statfs(&u16, &C.VJSXStatFs) int
} $else {
	fn C.vjsx_statfs(&char, &C.VJSXStatFs) int
}

fn (ctx &Context) fs_statfs_value(stats C.VJSXStatFs, bigint bool) Value {
	result := ctx.js_object()
	for field, count in {
		'type':   stats.fs_type
		'bsize':  stats.bsize
		'frsize': stats.frsize
		'blocks': stats.blocks
		'bfree':  stats.bfree
		'bavail': stats.bavail
		'files':  stats.files
		'ffree':  stats.ffree
	} {
		value := if bigint { ctx.js_big_uint(count) } else { ctx.js_float(f64(count)) }
		result.set(field, value)
		value.free()
	}
	return result
}

fn (ctx &Context) fs_statfs_error(message string, name string, code string) Value {
	value := ctx.js_error(message: message, name: name)
	value.set('code', code)
	return value
}

fn (ctx &Context) fs_statfs_export(roots []string) Value {
	return ctx.js_function(fn [ctx, roots] (args []Value) Value {
		promise := ctx.js_promise()
		if args.len == 0 || !args[0].is_string() {
			return promise.reject(ctx.fs_statfs_error('statfs path must be a string', 'TypeError',
				'ERR_INVALID_ARG_TYPE'))
		}
		path := fs_path_string(args[0]) or {
			return promise.reject(ctx.fs_statfs_error(err.msg(),
				'TypeError', 'ERR_INVALID_ARG_VALUE'))
		}
		bigint := if args.len > 1 {
			bool_option(args[1], 'bigint', false) or {
				return promise.reject(ctx.fs_statfs_error(err.msg(), 'TypeError', 'ERR_INVALID_ARG_TYPE'))
			}
		} else {
			false
		}
		policy := ctx.capability_policy()
		candidates := if path == '' {
			[]string{}
		} else {
			readable_candidate_paths(path, roots, policy)
		}
		if path != '' && candidates.len == 0 {
			return promise.reject(ctx.fs_statfs_error('filesystem read path is not allowed: ${path}',
				'Error', 'EACCES'))
		}
		mut status := C.ENOENT
		for candidate in candidates {
			mut stats := C.VJSXStatFs{}
			status = $if windows {
				C.vjsx_statfs(os.abs_path(candidate).to_wide(), &stats)
			} $else {
				C.vjsx_statfs(&char(candidate.str), &stats)
			}
			if status == 0 {
				return promise.resolve(ctx.fs_statfs_value(stats, bigint))
			}
			if status != C.ENOENT && status != C.ENOTDIR {
				break
			}
		}
		code := match status {
			C.ENOENT { 'ENOENT' }
			C.ENOTDIR { 'ENOTDIR' }
			C.EACCES { 'EACCES' }
			C.EPERM { 'EPERM' }
			else { 'EIO' }
		}
		return promise.reject(ctx.fs_statfs_error('statfs failed for ${path}: ${code}', 'Error', code))
	})
}
