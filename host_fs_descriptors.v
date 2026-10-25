module vjsx

import os

fn C.fsync(int) int
fn C._commit(int) int

struct FsDescriptor {
mut:
	file     os.File
	writable bool
}

@[heap]
struct FsDescriptors {
mut:
	files   map[int]FsDescriptor
	next_id int = 100
}

// These are virtual handles scoped to a Context, never arbitrary process fds.
fn (ctx &Context) fs_descriptor_exports(roots []string) Value {
	mut state := &FsDescriptors{}
	exports := ctx.js_object()
	open := ctx.js_function(fn [ctx, roots, mut state] (args []Value) Value {
		if args.len < 2 { return ctx.js_throw('path and flags are required') }
		flag := args[1].str()
		if flag !in ['r', 'w', 'wx', 'a'] { return ctx.js_throw('Unsupported openSync flags') }
		if state.files.len >= 128 { return ctx.js_throw('File descriptor limit reached') }
		writing := flag != 'r'
		path := if writing {
			writable_target_path(args[0].str(), roots, ctx.capability_policy()) or { return ctx.js_throw(err.msg()) }
		} else {
			resolve_existing_path(args[0].str(), roots, ctx.capability_policy()) or { return ctx.js_throw(err.msg()) }
		}
		mode := if args.len > 2 { args[2].to_int() } else { 0o666 }
		file := os.open_file(path, flag, mode) or { return ctx.js_throw(err.msg()) }
		id := state.next_id
		state.next_id++
		state.files[id] = FsDescriptor{ file: file, writable: writing }
		return ctx.js_int(id)
	})
	exports.set('openSync', open)
	open.free()
	write := ctx.js_function(fn [ctx, mut state] (args []Value) Value {
		if args.len != 2 {
			return ctx.js_throw('writeSync supports fd and data; positional writes are unsupported')
		}
		id := args[0].to_int()
		mut descriptor := state.files[id] or { return ctx.js_throw('Invalid file descriptor') }
		if !descriptor.writable { return ctx.js_throw('File descriptor is read-only') }
		bytes := if args[1].is_string() {
			args[1].str().bytes()
		} else {
			fs_value_to_bytes(args[1]) or { return ctx.js_throw(err.msg()) }
		}
		n := descriptor.file.write(bytes) or { return ctx.js_throw(err.msg()) }
		state.files[id] = descriptor
		return ctx.js_int(n)
	})
	exports.set('writeSync', write)
	write.free()
	fsync := ctx.js_function(fn [ctx, mut state] (args []Value) Value {
		id := args[0].to_int()
		mut descriptor := state.files[id] or { return ctx.js_throw('Invalid file descriptor') }
		descriptor.file.flush()
		result := $if windows { C._commit(descriptor.file.fd) } $else { C.fsync(descriptor.file.fd) }
		if result != 0 { return ctx.js_throw('fsyncSync failed') }
		return ctx.js_undefined()
	})
	exports.set('fsyncSync', fsync)
	fsync.free()
	close := ctx.js_function(fn [ctx, mut state] (args []Value) Value {
		id := args[0].to_int()
		mut descriptor := state.files[id] or { return ctx.js_throw('Invalid file descriptor') }
		descriptor.file.close()
		state.files.delete(id)
		return ctx.js_undefined()
	})
	exports.set('closeSync', close)
	close.free()
	rename := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len != 2 { return ctx.js_throw('source and destination are required') }
		src := writable_target_path(args[0].str(), roots, ctx.capability_policy()) or { return ctx.js_throw(err.msg()) }
		dst := writable_target_path(args[1].str(), roots, ctx.capability_policy()) or { return ctx.js_throw(err.msg()) }
		os.rename(src, dst) or { return ctx.js_throw(err.msg()) }
		return ctx.js_undefined()
	})
	exports.set('renameSync', rename)
	rename.free()
	ctx.register_host_cleanup(fn [mut state] () {
		for _, mut descriptor in state.files { descriptor.file.close() }
		state.files.clear()
	})
	return exports
}
