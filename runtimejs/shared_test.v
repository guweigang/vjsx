module runtimejs

fn test_mirrored_runtime_path_sanitizes_windows_drive_prefix() {
	path := mirrored_runtime_path('C:\\Temp\\vjsx-build', 'C:\\Users\\runner\\kernel_bootstrap.mts')
	normalized := path.replace('\\', '/')

	assert normalized.ends_with('/_drive_c/Users/runner/kernel_bootstrap.mts')
	assert !normalized.contains('/C:/')
}

fn test_mirrored_runtime_path_uses_relative_mirror_base() {
	path := mirrored_runtime_path_from('C:\\Temp\\vjsx-check\\stock-sdk',
		'C:\\Users\\a\\Documents\\AI Data Studio\\workspaces\\sqlite-local-demo-sqlite-local\\node_modules\\.vjsx-install-8480\\node_modules\\stock-sdk\\dist\\index.js',
		'C:\\Users\\a\\Documents\\AI Data Studio\\workspaces\\sqlite-local-demo-sqlite-local\\node_modules\\.vjsx-install-8480')
	normalized := path.replace('\\', '/')

	assert normalized.ends_with('/node_modules/stock-sdk/dist/index.js')
	assert !normalized.contains('/_drive_c/')
	assert !normalized.contains('/Users/a/Documents/AI Data Studio/')
}
