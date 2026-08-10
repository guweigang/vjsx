import os
import vjsx

fn test_app_executable_footer_round_trip_and_corruption_check() {
	root := os.join_path(os.temp_dir(), 'vjsx_app_executable_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	runner_path := os.join_path(root, 'runner')
	output_path := os.join_path(root, 'app')
	os.write_file_array(runner_path, [u8(1), 2, 3, 4]) or { panic(err) }

	mut compiler := vjsx.new_runtime_session()
	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name:   'vjsx-bundle/footer/main.mjs'
			source: 'export const value = 42;'
		},
	],
		app_name:        'footer'
		entry:           'vjsx-bundle/footer/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	vjsx.pack_app_executable(runner_path, bundle, output_path) or { panic(err) }
	loaded := vjsx.read_appended_bundle(output_path) or { panic(err) }
	assert loaded == bundle

	mut corrupted := os.read_bytes(output_path) or { panic(err) }
	corrupted[1] ^= u8(1)
	// Changing runner bytes is allowed because the footer protects the bundle.
	os.write_file_array(output_path, corrupted) or { panic(err) }
	loaded_after_runner_change := vjsx.read_appended_bundle(output_path) or { panic(err) }
	assert loaded_after_runner_change == bundle
	corrupted[4 + bundle.len - 1] ^= u8(1)
	os.write_file_array(output_path, corrupted) or { panic(err) }
	vjsx.read_appended_bundle(output_path) or {
		assert err.msg().contains('bundle checksum mismatch')
		return
	}
	assert false
}
