module vjsx

import compress.gzip

fn embedded_gzip_expect_error(data []u8) {
	if _ := decode_embedded_gzip_asset(data) {
		assert false
	}
}

fn test_embedded_gzip_native_matches_reference_for_compiler_asset() {
	bytes := runtime_asset_typescript_js_gz.to_bytes()
	expected := gzip.decompress(bytes) or { panic(err) }
	actual := runtime_embedded_gzip_asset_source(runtime_asset_typescript_js_gz) or { panic(err) }
	assert actual.bytes() == expected
}

fn test_embedded_gzip_native_preserves_empty_and_binary_payloads() {
	for plain in [[]u8{}, [u8(0), 1, 255, 0, 128], 'text with repeated content'.repeat(100).bytes()] {
		bytes := gzip.compress(plain) or { panic(err) }
		actual := decode_embedded_gzip_asset(bytes) or { panic(err) }
		assert actual.bytes() == plain
	}
}

fn test_embedded_gzip_native_rejects_header_payload_crc_and_length_corruption() {
	valid := gzip.compress('embedded asset'.repeat(32).bytes()) or { panic(err) }
	embedded_gzip_expect_error([]u8{})
	embedded_gzip_expect_error(valid[..8])
	for index in [0, 2, valid.len - 8, valid.len - 4] {
		mut bad := valid.clone()
		bad[index] ^= u8(1)
		embedded_gzip_expect_error(bad)
	}
	mut bad_payload := valid.clone()
	bad_payload[10] = u8(255)
	embedded_gzip_expect_error(bad_payload)
}

fn test_embedded_gzip_native_rejects_trailing_payload_and_concatenated_members() {
	valid := gzip.compress('embedded asset'.bytes()) or { panic(err) }
	mut extra := valid[..valid.len - 8].clone()
	extra << u8(0)
	extra << valid[valid.len - 8..]
	embedded_gzip_expect_error(extra)
	mut multiple := valid.clone()
	multiple << valid
	embedded_gzip_expect_error(multiple)
}

fn test_embedded_gzip_native_rejects_oversized_declared_length_before_allocation() {
	mut bytes := gzip.compress('small'.bytes()) or { panic(err) }
	for i in bytes.len - 4 .. bytes.len { bytes[i] = u8(255) }
	embedded_gzip_expect_error(bytes)
}

fn test_embedded_gzip_native_results_are_owned_and_concurrent() {
	plain := 'independent owned buffers'.repeat(256)
	bytes := gzip.compress(plain.bytes()) or { panic(err) }
	mut tasks := []thread{}
	for _ in 0 .. 16 {
		tasks << spawn fn [bytes, plain] () {
			for _ in 0 .. 16 {
				result := decode_embedded_gzip_asset(bytes) or { panic(err) }
				assert result == plain
			}
		}()
	}
	tasks.wait()
	first := decode_embedded_gzip_asset(bytes) or { panic(err) }
	_ := decode_embedded_gzip_asset(bytes) or { panic(err) }
	assert first == plain
}
