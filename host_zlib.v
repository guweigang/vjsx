module vjsx

import compress.deflate

fn zlib_input_bytes(ctx &Context, value Value) ![]u8 {
	if value.instanceof('ArrayBuffer') {
		return value.to_bytes()
	}
	array_buffer := ctx.js_global('ArrayBuffer')
	defer {
		array_buffer.free()
	}
	is_view_fn := array_buffer.get('isView')
	defer {
		is_view_fn.free()
	}
	is_view := ctx.call_this(array_buffer, is_view_fn, value)!
	defer {
		is_view.free()
	}
	if is_view.to_bool() && !value.instanceof('DataView') {
		buffer := value.get('buffer')
		defer {
			buffer.free()
		}
		bytes := buffer.to_bytes()
		offset_value := value.get('byteOffset')
		length_value := value.get('byteLength')
		defer {
			offset_value.free()
			length_value.free()
		}
		offset := offset_value.to_int()
		length := length_value.to_int()
		return bytes[offset..offset + length].clone()
	}
	return error('data must be an ArrayBuffer or TypedArray')
}

fn zlib_validate_options(value Value) ! {
	if value.is_undefined() || value.is_null() {
		return
	}
	if !value.is_object() {
		return error('options must be an object')
	}
	level_value := value.get('level')
	defer {
		level_value.free()
	}
	if level_value.is_undefined() || level_value.is_null() {
		return
	}
	if !level_value.is_number() {
		return error('options.level must be a number')
	}
	raw_level := level_value.to_f64()
	level := int(raw_level)
	if raw_level != f64(level) {
		return error('options.level must be an integer')
	}
	if level !in [-1, 9] {
		return error('V compress.deflate currently supports only the default level or level 9 compatibility mode')
	}
}

// Install the synchronous raw DEFLATE subset used by deterministic ZIP writers.
pub fn (ctx &Context) install_zlib_module() {
	deflate_raw_sync := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'data is required', name: 'TypeError'))
		}
		bytes := zlib_input_bytes(ctx, args[0]) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		if args.len > 1 {
			zlib_validate_options(args[1]) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		}
		compressed := deflate.compress_raw(bytes) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		return fs_bytes_value(ctx, compressed)
	})
	for module_name in ['zlib', 'node:zlib'] {
		mut zlib_mod := ctx.js_module(module_name)
		default_obj := ctx.js_object()
		zlib_mod.export('deflateRawSync', deflate_raw_sync)
		default_obj.set('deflateRawSync', deflate_raw_sync)
		zlib_mod.export_default(default_obj)
		zlib_mod.create()
		default_obj.free()
	}
	deflate_raw_sync.free()
}
