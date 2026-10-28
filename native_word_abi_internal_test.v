module vjsx

import os
import time

fn test_javascript_signed_int32_conversion_preserves_c_output_width() {
	assert sizeof(i32) == 4
	mut session := new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	for expected in [int(-2147483648), -1, 0, 1, 2147483647] {
		value := ctx.eval('${expected}')!
		assert value.to_int() == expected
		value.free()
	}
	wrapped := ctx.eval('2147483648')!
	assert wrapped.to_int() == -2147483648
	wrapped.free()
}

fn test_native_process_wait_preserves_c_int_exit_status() {
	$if !windows {
		for expected in [0, 7] {
			output := os.join_path(os.temp_dir(), 'vjsx-native-c-word-${os.getpid()}-${time.now().unix_micro()}.log')
			defer { os.rm(output) or {} }
			mut process := start_curl_process('/bin/sh', ['-c', 'exit ${expected}'], output)!
			process.reap()
			assert process.done
			assert process.exit_code == expected
		}
	}
}
