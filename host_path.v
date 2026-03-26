module vjsx

import os

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
