module vjsx

import os

#include "@VMODROOT/native/fs_watch.h"

$if windows {
	fn C.vjsx_fs_watch_subsecond(&u16) i64
} $else {
	fn C.vjsx_fs_watch_subsecond(&char, int) i64
}

struct FsWatchDirectory {
	path     string
	relative string
}

fn fs_watch_stamp(ctx &Context, path string, st os.Stat, follow bool) Value {
	kind := st.get_filetype()
	stamp := ctx.js_array()
	stamp.set(0, '${st.dev}:${st.inode}:${int(kind)}')
	if kind != .directory {
		subsecond := $if windows {
			C.vjsx_fs_watch_subsecond(path.to_wide())
		} $else {
			C.vjsx_fs_watch_subsecond(&char(path.str), int(follow))
		}
		stamp.set(1, '${st.size}:${st.mtime}:${subsecond}:${st.ctime}:${st.mode}')
	}
	return stamp
}

fn (ctx &Context) fs_watch_snapshot(path string, recursive bool) !Value {
	policy := ctx.capability_policy()
	if !policy.allow_fs_read || !fs_path_within_roots(path, policy.fs_read_roots) {
		return error('filesystem watch path is not allowed: ${path}')
	}
	st := os.stat(path) or {
		if !os.exists(path) {
			return ctx.js_null()
		}
		return err
	}
	root := fs_watch_stamp(ctx, path, st, true)
	defer {
		root.free()
	}
	entries := ctx.js_array()
	defer {
		entries.free()
	}
	is_dir := st.get_filetype() == .directory
	if is_dir {
		mut directories := [FsWatchDirectory{ path: path }]
		mut index := 0
		for directories.len > 0 {
			dir := directories.pop()
			if !fs_path_within_roots(dir.path, policy.fs_read_roots) {
				continue
			}
			names := os.ls(dir.path) or {
				if !os.exists(dir.path) {
					if dir.relative == '' {
						return ctx.js_null()
					}
					continue
				}
				return err
			}
			for name in names {
				child := os.join_path(dir.path, name)
				stat := os.lstat(child) or { continue }
				rel := if dir.relative == '' { name } else { os.join_path(dir.relative, name) }
				row := fs_watch_stamp(ctx, child, stat, false)
				row.set(2, rel)
				entries.set(index, row)
				row.free()
				index++
				if recursive && stat.get_filetype() == .directory {
					directories << FsWatchDirectory{
						path:     child
						relative: rel
					}
				}
			}
		}
	}

	snapshot := ctx.js_object()
	snapshot.set('root', root)
	snapshot.set('entries', entries)
	if is_dir {
		snapshot.set('filename', ctx.js_null())
	} else {
		snapshot.set('filename', os.base(path))
	}
	return snapshot
}

fn (ctx &Context) fs_watch_error(message string, code string) Value {
	value := ctx.js_error(message: message)
	value.set('code', code)
	return ctx.js_throw(value)
}

fn (ctx &Context) fs_watch_export(roots []string) !Value {
	source := $embed_file('web/js/fs_watch.js')
	value := ctx.js_eval(source.to_string(), 'vjsx://web/js/fs_watch.js', type_module)!
	value.free()
	factory := ctx.js_global('__vjsxCreateFsWatch')
	defer {
		factory.free()
	}
	resolve := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		path := args[0].str()
		policy := ctx.capability_policy()
		allowed := readable_candidate_paths(path, roots, policy)
		if allowed.len == 0 {
			return ctx.fs_watch_error('filesystem watch path is not allowed: ${path}', 'EACCES')
		}
		for candidate in allowed {
			if os.exists(candidate) {
				return ctx.js_string(os.abs_path(candidate))
			}
		}
		return ctx.fs_watch_error('watch path not found: ${path}', 'ENOENT')
	})
	defer {
		resolve.free()
	}
	snapshot := ctx.js_function(fn [ctx] (args []Value) Value {
		return ctx.fs_watch_snapshot(args[0].str(), args[1].to_bool()) or {
			ctx.fs_watch_error(err.msg(), 'EIO')
		}
	})
	defer {
		snapshot.free()
	}
	api := ctx.call(factory, resolve, snapshot)!
	defer {
		api.free()
	}
	cleanup := api.get('cleanup')
	ctx.register_host_cleanup(fn [ctx, cleanup] () {
		result := ctx.call(cleanup) or { ctx.js_undefined() }
		result.free()
		cleanup.free()
	})
	return api.get('watch')
}
