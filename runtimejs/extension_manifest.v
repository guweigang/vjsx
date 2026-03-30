module runtimejs

import vjsx

pub struct ExtensionServiceBinding {
pub:
	name        string
	export_name string
	method_name string
}

// ExtensionManifest describes metadata declared by a JS/TS extension through
// `export const extension = { ... }`.
pub struct ExtensionManifest {
pub:
	path            string
	name            string
	capabilities    []string
	services        []ExtensionServiceBinding
	activate_export string = 'activate'
	handle_export   string = 'handle'
	dispose_export  string = 'dispose'
}

fn extension_manifest_defaults(path string) ExtensionManifest {
	return ExtensionManifest{
		path: path
		name: path
	}
}

fn extension_manifest_string_prop(obj vjsx.Value, key string) string {
	value := obj.get(key)
	defer {
		value.free()
	}
	if value.is_undefined() || value.is_null() || !value.is_string() {
		return ''
	}
	return value.to_string()
}

fn extension_manifest_string_array_prop(obj vjsx.Value, key string) ![]string {
	value := obj.get(key)
	defer {
		value.free()
	}
	if value.is_undefined() || value.is_null() {
		return []string{}
	}
	if !value.is_array() {
		return error('extension.${key} must be an array of strings')
	}
	mut items := []string{cap: value.len()}
	for index in 0 .. value.len() {
		entry := value.get(index)
		if !entry.is_string() {
			entry.free()
			return error('extension.${key}[${index}] must be a string')
		}
		items << entry.to_string()
		entry.free()
	}
	return items
}

fn extension_manifest_hook_name(obj vjsx.Value, key string, fallback string) string {
	direct := extension_manifest_string_prop(obj, key)
	if direct != '' {
		return direct
	}
	hooks := obj.get('hooks')
	defer {
		hooks.free()
	}
	if hooks.is_undefined() || hooks.is_null() || !hooks.is_object() {
		return fallback
	}
	nested := extension_manifest_string_prop(hooks, key)
	if nested != '' {
		return nested
	}
	return fallback
}

fn extension_manifest_service_from_value(service_name string, value vjsx.Value) !ExtensionServiceBinding {
	if value.is_string() {
		return ExtensionServiceBinding{
			name:        service_name
			export_name: value.to_string()
		}
	}
	if !value.is_object() {
		return error('extension.services.${service_name} must be a string or object')
	}
	export_name := extension_manifest_string_prop(value, 'export')
	method_name := extension_manifest_string_prop(value, 'method')
	return ExtensionServiceBinding{
		name:        service_name
		export_name: if export_name != '' { export_name } else { service_name }
		method_name: method_name
	}
}

fn extension_manifest_services(obj vjsx.Value) ![]ExtensionServiceBinding {
	value := obj.get('services')
	defer {
		value.free()
	}
	if value.is_undefined() || value.is_null() {
		return []ExtensionServiceBinding{}
	}
	if !value.is_object() {
		return error('extension.services must be an object')
	}
	props := value.property_names()!
	mut services := []ExtensionServiceBinding{cap: props.len}
	for prop in props {
		service_name := prop.atom.to_string()
		entry := value.get(prop)
		service := extension_manifest_service_from_value(service_name, entry)!
		entry.free()
		services << service
	}
	return services
}

pub fn extension_manifest_from_module(path string, module_handle vjsx.ScriptModule) !ExtensionManifest {
	defaults := extension_manifest_defaults(path)
	if !module_handle.has_export('extension') {
		return defaults
	}
	metadata := module_handle.get_export('extension')!
	defer {
		metadata.free()
	}
	if !metadata.is_object() {
		return error('extension export must be an object')
	}
	name := extension_manifest_string_prop(metadata, 'name')
	capabilities := extension_manifest_string_array_prop(metadata, 'capabilities')!
	services := extension_manifest_services(metadata)!
	activate_export := extension_manifest_hook_name(metadata, 'activate', defaults.activate_export)
	handle_export := extension_manifest_hook_name(metadata, 'handle', defaults.handle_export)
	dispose_export := extension_manifest_hook_name(metadata, 'dispose', defaults.dispose_export)
	return ExtensionManifest{
		path:            defaults.path
		name:            if name != '' { name } else { defaults.name }
		capabilities:    capabilities
		services:        services
		activate_export: activate_export
		handle_export:   handle_export
		dispose_export:  dispose_export
	}
}

pub fn extension_manifest_apply_hooks(manifest ExtensionManifest, hooks vjsx.ScriptPluginHooks) vjsx.ScriptPluginHooks {
	return vjsx.ScriptPluginHooks{
		name:                  if hooks.name != '' { hooks.name } else { manifest.name }
		activate_export:       if hooks.activate_export != 'activate' {
			hooks.activate_export
		} else {
			manifest.activate_export
		}
		handle_export:         if hooks.handle_export != 'handle' {
			hooks.handle_export
		} else {
			manifest.handle_export
		}
		dispose_export:        if hooks.dispose_export != 'dispose' {
			hooks.dispose_export
		} else {
			manifest.dispose_export
		}
		capabilities:          if hooks.capabilities.len > 0 {
			hooks.capabilities.clone()
		} else {
			manifest.capabilities.clone()
		}
		auto_dispose_on_close: hooks.auto_dispose_on_close
	}
}
