module runtimejs

fn test_mirrored_runtime_path_sanitizes_windows_drive_prefix() {
	path := mirrored_runtime_path('C:\\Temp\\vjsx-build', 'C:\\Users\\runner\\kernel_bootstrap.mts')
	normalized := path.replace('\\', '/')

	assert normalized.ends_with('/_drive_c/Users/runner/kernel_bootstrap.mts')
	assert !normalized.contains('/C:/')
}
