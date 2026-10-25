module vjsx

import os
import net.urllib

fn (ctx &Context) install_node_url_module() {
	factory := ctx.eval('(href) => new URL(href)') or { panic(err) }
	path_to_url := ctx.js_function(fn [ctx, factory] (args []Value) Value {
		if args.len != 1 || !args[0].is_string() {
			return ctx.js_throw('pathToFileURL requires a path string')
		}
		raw := args[0].str()
		absolute := os.abs_path(raw).replace('\\', '/')
		mut escaped := absolute.split('/').map(urllib.path_escape(it)).join('/')
		$if windows {
			escaped = escaped.replace('%3A', ':')
		}
		if raw.ends_with('/') && !escaped.ends_with('/') { escaped += '/' }
		href := 'file://' + if escaped.starts_with('/') { escaped } else { '/' + escaped }
		return ctx.call(factory, href) or { ctx.js_throw(err.msg()) }
	})
	file_to_path := ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len != 1 { return ctx.js_throw('fileURLToPath requires a URL') }
		value := if args[0].is_string() { args[0].dup_value() } else { args[0].get('href') }
		raw := value.str()
		value.free()
		if !raw.to_lower().starts_with('file://') { return ctx.js_throw('Invalid local file URL') }
		rest := raw[7..].all_before('#').all_before('?')
		slash := rest.index('/') or { return ctx.js_throw('File URL requires an absolute path') }
		if rest[..slash].to_lower() !in ['', 'localhost'] {
			return ctx.js_throw('Non-local file URL is unsupported')
		}
		escaped := rest[slash..]
		if escaped.to_lower().contains('%2f') {
			return ctx.js_throw('Encoded path separator is invalid')
		}
		$if windows {
			if escaped.to_lower().contains('%5c') {
				return ctx.js_throw('Encoded path separator is invalid')
			}
		}
		path := urllib.path_unescape(escaped) or { return ctx.js_throw(err.msg()) }
		if path.contains('\x00') { return ctx.js_throw('File URL contains a null byte') }
		$if windows {
			return ctx.js_string(path.trim_left('/').replace('/', '\\'))
		}
		return ctx.js_string(path)
	})
	for name in ['url', 'node:url'] {
		mut mod := ctx.js_module(name)
		default_obj := ctx.js_object()
		for key in ['URL', 'URLSearchParams'] {
			value := ctx.js_global(key)
			mod.export(key, value)
			default_obj.set(key, value)
			value.free()
		}
		mod.export('pathToFileURL', path_to_url)
		default_obj.set('pathToFileURL', path_to_url)
		mod.export('fileURLToPath', file_to_path)
		default_obj.set('fileURLToPath', file_to_path)
		mod.export_default(default_obj)
		mod.create()
		default_obj.free()
	}
	path_to_url.free()
	file_to_path.free()
	ctx.register_host_cleanup(fn [factory] () { factory.free() })
}
