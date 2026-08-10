module vjsx

import crypto.sha256
import os
import time

const app_executable_magic = [u8(`V`), `J`, `S`, `X`, `A`, `P`, `P`, 0]
const app_executable_format_version = u16(1)
const app_executable_footer_size = 64

fn app_executable_footer(bundle []u8) []u8 {
	mut footer := []u8{cap: app_executable_footer_size}
	footer << app_executable_magic
	append_u16_le(mut footer, app_executable_format_version)
	append_u16_le(mut footer, 0)
	append_u64_le(mut footer, u64(bundle.len))
	footer << sha256.sum256(bundle)
	footer << []u8{len: 12}
	return footer
}

// PackAppExecutableOptions controls creation of a single-file executable.
@[params]
pub struct PackAppExecutableOptions {
pub:
	overwrite bool = true
}

fn append_app_executable_payload(path string, bundle []u8) ! {
	mut output := os.open_append(path)!
	defer {
		output.close()
	}
	written_bundle := output.write(bundle)!
	if written_bundle != bundle.len {
		return error('incomplete vjsx app bundle write: wrote ${written_bundle} of ${bundle.len} bytes')
	}
	footer := app_executable_footer(bundle)
	written_footer := output.write(footer)!
	if written_footer != footer.len {
		return error('incomplete vjsx app footer write: wrote ${written_footer} of ${footer.len} bytes')
	}
}

// pack_app_executable copies an unbundled native app runner and appends a
// `.vjsx` bundle plus a fixed footer. The resulting file remains a native
// executable while the runner can locate the bundle from its own file tail.
pub fn pack_app_executable(runner_path string, bundle []u8, output_path string, options PackAppExecutableOptions) ! {
	if bundle.len == 0 {
		return error('cannot pack an empty vjsx bundle')
	}
	if !os.is_file(runner_path) {
		return error('vjsx app runner not found: ${runner_path}')
	}
	if os.real_path(runner_path) == os.real_path(output_path) {
		return error('vjsx app output must differ from the runner path')
	}
	if os.is_dir(output_path) {
		return error('vjsx app output is a directory: ${output_path}')
	}
	if os.exists(output_path) && !options.overwrite {
		return error('vjsx app output already exists: ${output_path}')
	}
	output_dir := os.dir(output_path)
	if output_dir != '' && output_dir != '.' {
		os.mkdir_all(output_dir)!
	}
	temp_path := '${output_path}.vjsx-pack-${os.getpid()}-${time.now().unix_micro()}'
	defer {
		os.rm(temp_path) or {}
	}
	os.cp(runner_path, temp_path)!
	append_app_executable_payload(temp_path, bundle)!
	$if !windows {
		os.chmod(temp_path, 0o755)!
	} $else {
		if os.exists(output_path) {
			os.rm(output_path)!
		}
	}
	os.mv(temp_path, output_path)!
}

// read_appended_bundle validates and reads the `.vjsx` payload appended to a
// native vjsx app runner. It reads only the footer and bundle, not the runner.
pub fn read_appended_bundle(executable_path string) ![]u8 {
	if !os.is_file(executable_path) {
		return error('vjsx app executable not found: ${executable_path}')
	}
	file_size := os.file_size(executable_path)
	if file_size < app_executable_footer_size {
		return error('invalid vjsx app executable: truncated footer')
	}
	mut file := os.open(executable_path)!
	defer {
		file.close()
	}
	footer_offset := file_size - app_executable_footer_size
	footer := file.read_bytes_at(app_executable_footer_size, footer_offset)
	if footer.len != app_executable_footer_size {
		return error('invalid vjsx app executable: truncated footer')
	}
	if footer[..app_executable_magic.len] != app_executable_magic {
		return error('invalid vjsx app executable: embedded bundle footer not found')
	}
	format_version := read_u16_le(footer, 8)!
	if format_version != app_executable_format_version {
		return error('incompatible vjsx app executable format: artifact=${format_version}, runtime=${app_executable_format_version}')
	}
	bundle_len := read_u64_le(footer, 12)!
	if bundle_len == 0 || bundle_len > footer_offset {
		return error('invalid vjsx app executable: bad bundle length')
	}
	bundle_offset := footer_offset - bundle_len
	if bundle_len > u64(max_int) {
		return error('invalid vjsx app executable: bundle is too large')
	}
	bundle := file.read_bytes_at(int(bundle_len), bundle_offset)
	if bundle.len != int(bundle_len) {
		return error('invalid vjsx app executable: truncated bundle')
	}
	if sha256.sum256(bundle) != footer[20..52] {
		return error('invalid vjsx app executable: bundle checksum mismatch')
	}
	// Validate the inner container before the runner initializes QuickJS.
	bundle_info(bundle)!
	return bundle
}
