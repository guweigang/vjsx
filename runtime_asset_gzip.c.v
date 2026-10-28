module vjsx

import compress.deflate
import encoding.binary
import v.embed_file
import log
import time

// Use the native DEFLATE decoder already shipped with V. Embedded compiler
// assets are large: interpreting every match through the V decoder on each
// lane can exhaust the host's initialization deadline in unoptimized builds.
#flag -I @VEXEROOT/thirdparty/zip
#flag -I @VMODROOT
#include "runtime_asset_gzip.h"

fn C.vjsx_inflate_embedded_asset(input voidptr, input_size uint, output voidptr, output_capacity uint, output_size &uint) i32

fn C.vjsx_embedded_asset_crc32(bytes voidptr, size uint) u32

fn runtime_embedded_gzip_asset_source(asset &embed_file.EmbedFileData) !string {
	started := time.sys_mono_now()
	log.debug('[vjsx] embedded gzip decode begin')
	source := decode_embedded_gzip_asset(asset.to_bytes())!
	elapsed_ms := (time.sys_mono_now() - started) / 1_000_000
	log.debug('[vjsx] embedded gzip decode done bytes=${source.len} elapsed_ms=${elapsed_ms}')
	return source
}

// This decoder is only for trusted, single-member, build-time embedded assets.
// External asset overrides still follow the normal filesystem/source loader.
fn decode_embedded_gzip_asset(bytes []u8) !string {
	header := deflate.validate_gzip_header(bytes)!
	trailer := bytes.len - 8
	payload := bytes[header.payload_start..trailer]
	expected_crc := binary.little_endian_u32_at(bytes, trailer)
	expected_size := binary.little_endian_u32_at(bytes, trailer + 4)

	if u64(expected_size) > u64(0x7fffffff) {
		return error('invalid embedded gzip asset: size exceeds supported limit')
	}
	mut data := []u8{len: if expected_size == 0 { 1 } else { int(expected_size) }}
	mut decoded_len := uint(0)
	if C.vjsx_inflate_embedded_asset(payload.data, uint(payload.len), data.data,
		uint(data.len), &decoded_len) != 1 {
		return error('invalid embedded gzip asset: DEFLATE decode failed')
	}
	if decoded_len != uint(expected_size) {
		return error('invalid embedded gzip asset: size mismatch')
	}
	// Borrow only until bytestr copies the result into its own string storage.
	decoded := unsafe { data[..int(decoded_len)] }
	if C.vjsx_embedded_asset_crc32(decoded.data, decoded_len) != expected_crc {
		return error('invalid embedded gzip asset: crc32 mismatch')
	}
	return decoded.bytestr()
}
