module runtimejs

fn test_mirrored_runtime_path_sanitizes_windows_drive_prefix() {
	path := mirrored_runtime_path('C:\\Temp\\vjsx-build', 'C:\\Users\\runner\\kernel_bootstrap.mts')
	normalized := path.replace('\\', '/')

	assert normalized.ends_with('/_drive_c/Users/runner/kernel_bootstrap.mts')
	assert !normalized.contains('/C:/')
}

fn test_mirrored_runtime_path_uses_relative_mirror_base() {
	path := mirrored_runtime_path_from('C:\\Temp\\vjsx-check\\stock-sdk', 'C:\\Users\\a\\Documents\\AI Data Studio\\workspaces\\sqlite-local-demo-sqlite-local\\node_modules\\.vjsx-install-8480\\node_modules\\stock-sdk\\dist\\index.js', 'C:\\Users\\a\\Documents\\AI Data Studio\\workspaces\\sqlite-local-demo-sqlite-local\\node_modules\\.vjsx-install-8480')
	normalized := path.replace('\\', '/')

	assert normalized.ends_with('/node_modules/stock-sdk/dist/index.js')
	assert !normalized.contains('/_drive_c/')
	assert !normalized.contains('/Users/a/Documents/AI Data Studio/')
}

fn test_http_module_aliases_are_native_builtins() {
	for name in ['http', 'node:http', 'https', 'node:https'] {
		assert is_node_builtin_module_specifier(name)
	}
	assert !is_node_builtin_module_specifier('node:http/not-supported')
}
