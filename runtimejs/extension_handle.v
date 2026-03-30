module runtimejs

import vjsx

// ExtensionHandle combines bound lifecycle hooks with bound module export
// calls, so embedders can treat one JS/TS file like a single extension
// instance.
pub struct ExtensionHandle {
	services []ExtensionServiceBinding
mut:
	module vjsx.BoundScriptModule
	plugin vjsx.BoundScriptPlugin
}

// Report the configured extension name, or its resolved path when unnamed.
pub fn (extension ExtensionHandle) name() string {
	return extension.plugin.name()
}

// Report the resolved extension path.
pub fn (extension ExtensionHandle) path() string {
	return extension.plugin.path()
}

// Report the declared extension capabilities.
pub fn (extension ExtensionHandle) capabilities() []string {
	return extension.plugin.capabilities()
}

// Check whether the extension declares a named capability.
pub fn (extension ExtensionHandle) has_capability(name string) bool {
	return extension.plugin.has_capability(name)
}

// Report the declared extension services.
pub fn (extension ExtensionHandle) services() []ExtensionServiceBinding {
	return extension.services.clone()
}

// Check whether the extension declares a named service.
pub fn (extension ExtensionHandle) has_service(name string) bool {
	return extension.find_service(name) >= 0
}

// Report whether the extension has already been closed.
pub fn (extension ExtensionHandle) is_closed() bool {
	return extension.plugin.is_closed()
}

// Access the underlying bound module handle.
pub fn (extension ExtensionHandle) module_handle() vjsx.BoundScriptModule {
	return extension.module
}

// Access the underlying bound plugin handle.
pub fn (extension ExtensionHandle) plugin_handle() vjsx.BoundScriptPlugin {
	return extension.plugin
}

// Report whether a named export exists.
pub fn (extension ExtensionHandle) has_export(name string) bool {
	return extension.module.has_export(name)
}

// Return a duplicate of the module namespace object.
pub fn (extension ExtensionHandle) namespace() !vjsx.Value {
	return extension.module.namespace()
}

// Return a duplicate of a named export.
pub fn (extension ExtensionHandle) get_export(name string) !vjsx.Value {
	return extension.module.get_export(name)
}

// Return a duplicate of the default export.
pub fn (extension ExtensionHandle) default_export() !vjsx.Value {
	return extension.module.default_export()
}

// Run the extension activation hook with the bound host context.
pub fn (extension ExtensionHandle) activate(args ...vjsx.AnyValue) !vjsx.Value {
	return extension.plugin.activate(...args)
}

// Run the extension handler hook with the bound host context.
pub fn (extension ExtensionHandle) handle(args ...vjsx.AnyValue) !vjsx.Value {
	return extension.plugin.handle(...args)
}

// Run the extension dispose hook with the bound host context.
pub fn (extension ExtensionHandle) dispose(args ...vjsx.AnyValue) !vjsx.Value {
	return extension.plugin.dispose(...args)
}

// Call a named function export with the bound host context.
pub fn (extension ExtensionHandle) call_export(name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.module.call_export(name, ...args)
}

// Call a named export when it exists, otherwise return `undefined`.
pub fn (extension ExtensionHandle) call_export_if_present(name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.module.call_export_if_present(name, ...args)
}

// Call a method on an exported object with the bound host context.
pub fn (extension ExtensionHandle) call_export_method(export_name string, method_name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.module.call_export_method(export_name, method_name, ...args)
}

// Call a method on the default export object with the bound host context.
pub fn (extension ExtensionHandle) call_default_method(method_name string, args ...vjsx.AnyValue) !vjsx.Value {
	return extension.module.call_default_method(method_name, ...args)
}

fn (extension ExtensionHandle) find_service(name string) int {
	for index, service in extension.services {
		if service.name == name {
			return index
		}
	}
	return -1
}

// Call a declared extension service by service name.
pub fn (extension ExtensionHandle) call_service(name string, args ...vjsx.AnyValue) !vjsx.Value {
	index := extension.find_service(name)
	if index < 0 {
		return error('extension service not found: ${name}')
	}
	service := extension.services[index]
	if service.method_name != '' {
		return extension.call_export_method(service.export_name, service.method_name,
			...args)
	}
	return extension.call_export(service.export_name, ...args)
}

// Free the underlying bound handles. Safe to call more than once.
pub fn (mut extension ExtensionHandle) close() {
	extension.plugin.close()
	extension.module.close()
}
