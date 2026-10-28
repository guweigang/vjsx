module vjsx

pub type HostValueBuilder = fn (&Context) Value

pub type HostModuleInstaller = fn (&Context, mut Module)

@[params]
pub struct HostObjectField {
pub:
	name  string           @[required]
	value HostValueBuilder @[required]
}

@[params]
pub struct HostGlobalBinding {
pub:
	name  string           @[required]
	value HostValueBuilder @[required]
}

@[params]
pub struct HostModuleExport {
pub:
	name  string           @[required]
	value HostValueBuilder @[required]
}

@[params]
pub struct HostModuleBinding {
pub:
	name           string              @[required]
	install        HostModuleInstaller @[required]
	export_default bool = true
}

@[params]
pub struct HostApiConfig {
pub:
	globals []HostGlobalBinding
	modules []HostModuleBinding
}

// Wrap a literal/Value into a reusable host value builder.
pub fn host_value(any AnyValue) HostValueBuilder {
	return fn [any] (ctx &Context) Value {
		if any is Value {
			return (any as Value).dup_value()
		}
		return ctx.any_to_val(any)
	}
}

// Build a JS object value from a list of named host fields.
pub fn host_object(fields ...HostObjectField) HostValueBuilder {
	return fn [fields] (ctx &Context) Value {
		obj := ctx.js_object()
		for field in fields {
			value := field.value(ctx)
			obj.set(field.name, value)
			value.free()
		}
		return obj
	}
}

// Build a module installer from a list of exports.
pub fn host_module_exports(exports ...HostModuleExport) HostModuleInstaller {
	return fn [exports] (ctx &Context, mut mod Module) {
		for export in exports {
			value := export.value(ctx)
			mod.export(export.name, value)
			value.free()
		}
	}
}

// Build a module installer whose default export is a host object, while also
// re-exporting the same fields as named exports.
pub fn host_module_object(fields ...HostObjectField) HostModuleInstaller {
	return fn [fields] (ctx &Context, mut mod Module) {
		for field in fields {
			value := field.value(ctx)
			mod.export(field.name, value)
			value.free()
		}
	}
}

fn (ctx &Context) install_host_global(binding HostGlobalBinding) {
	global := ctx.js_global()
	value := binding.value(ctx)
	global.set(binding.name, value)
	value.free()
	global.free()
}

fn (ctx &Context) install_host_module(binding HostModuleBinding) {
	mut mod := ctx.js_module(binding.name)
	binding.install(ctx, mut mod)
	default_value := mod.get('default')
	has_default := !default_value.is_undefined()
	default_value.free()
	if binding.export_default && !has_default {
		default_obj := mod.to_object()
		mod.export_default(default_obj)
		default_obj.free()
	}
	mod.create()
}

// Install a formal host API surface for embedders.
// This keeps JS/TS extension capabilities explicit and reusable, without
// requiring callers to hand-roll module creation for every embedding site.
pub fn (ctx &Context) install_host_api(config HostApiConfig) {
	for binding in config.globals {
		ctx.install_host_global(binding)
	}
	for binding in config.modules {
		ctx.install_host_module(binding)
	}
}
