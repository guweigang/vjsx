module main

import os
import strconv

fn test_npm_curl_args_require_https_for_redirects() {
	args := npm_curl_args('https://registry.example/package', '/tmp/body', '/tmp/diagnostics')
	assert args.contains('--proto')
	assert args[args.index('--proto') + 1] == '=https'
	assert args.contains('--proto-redir')
	assert args[args.index('--proto-redir') + 1] == '=https'
}

fn test_npm_curl_download_uses_spawn_without_a_shell() {
	$if !windows {
		root := os.join_path(os.temp_dir(), 'vjsx_npm_curl_${os.getpid()}')
		os.rmdir_all(root) or {}
		os.mkdir_all(root) or { panic(err) }
		defer {
			os.rmdir_all(root) or {}
		}
		fake_curl := os.join_path(root, 'fake curl')
		body_path := os.join_path(root, 'body with spaces')
		diagnostics_path := os.join_path(root, 'diagnostics with spaces')
		os.write_file(fake_curl, '#!/bin/sh\nwhile [ "\$#" -gt 0 ]; do\n  if [ "\$1" = "--output" ]; then\n    shift\n    printf "downloaded" > "\$1"\n  fi\n  shift\ndone\n') or {
			panic(err)
		}
		os.chmod(fake_curl, 0o700) or { panic(err) }
		run_npm_curl(fake_curl, npm_curl_args('https://registry.example/package', body_path, diagnostics_path), diagnostics_path) or { panic(err) }
		assert os.read_file(body_path)! == 'downloaded'
	}
}

fn test_package_spec_parser_seed_corpus() {
	valid := {
		'left-pad':          'left-pad|'
		'left-pad@1.3.0':    'left-pad|1.3.0'
		'@scope/pkg':        '@scope/pkg|'
		'@scope/pkg@^2.0.0': '@scope/pkg|^2.0.0'
	}
	for input, expected in valid {
		parsed := parse_package_spec(input) or { panic('${input}: ${err}') }
		assert '${parsed.name}|${parsed.version}' == expected
	}
	for input in ['', '@scope', '@scope/', '../escape', 'a/b', '/absolute', 'a\\b', 'a..b'] {
		parse_package_spec(input) or { continue }
		assert false, 'package spec should be rejected: ${input}'
	}
}

fn test_npm_tar_path_parser_rejects_traversal_and_platform_absolute_seeds() {
	assert npm_tar_rel_path('package/lib/index.js')! == 'lib/index.js'
	assert npm_tar_rel_path('package/')! == ''
	for input in ['package/../escape', '../escape', '/absolute', 'package/C:/escape',
		'package/C:\\escape', 'package/lib/../../escape'] {
		npm_tar_rel_path(input) or { continue }
		assert false, 'tar path should be rejected: ${input}'
	}
}

fn write_tar_octal(mut header []u8, start int, width int, value int) {
	octal := strconv.format_int(i64(value), 8)
	if octal.len > width - 1 {
		panic('test octal value does not fit')
	}
	for index in 0 .. width {
		header[start + index] = 0
	}
	padding := width - 1 - octal.len
	for index in 0 .. padding {
		header[start + index] = `0`
	}
	for index, byte in octal.bytes() {
		header[start + padding + index] = byte
	}
}

fn tar_seed_header(name string, size int) []u8 {
	mut header := []u8{len: 512}
	for index, byte in name.bytes() {
		header[index] = byte
	}
	write_tar_octal(mut header, 124, 12, size)
	header[156] = `0`
	for index in 148 .. 156 {
		header[index] = ` `
	}
	mut checksum := 0
	for byte in header {
		checksum += int(byte)
	}
	write_tar_octal(mut header, 148, 8, checksum)
	return header
}

fn test_tar_validator_accepts_minimal_archive_and_rejects_seed_corruption() {
	mut raw := tar_seed_header('package/index.js', 1)
	raw << `x`
	raw << []u8{len: 511}
	raw << []u8{len: 512}
	validate_npm_tar(raw) or { panic(err) }

	mut bad_checksum := raw.clone()
	bad_checksum[0] ^= 1
	mut rejected_checksum := false
	validate_npm_tar(bad_checksum) or {
		assert err.msg().contains('checksum mismatch')
		rejected_checksum = true
	}
	assert rejected_checksum

	mut bad_size := raw.clone()
	bad_size[124] = `x`
	mut rejected_size := false
	validate_npm_tar(bad_size) or {
		assert err.msg().contains('octal') || err.msg().contains('checksum')
		rejected_size = true
	}
	assert rejected_size

	validate_npm_tar(raw[..raw.len - 512]) or {
		assert err.msg().contains('missing end marker')
		return
	}
	assert false
}
