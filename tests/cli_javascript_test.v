import os
import tests.cli_test_support

fn test_cli_run_file() {
	output := os.execute('${cli_test_support.command(false)} ./tests/test.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'test foo'
}

fn test_cli_run_commonjs_file() {
	output := os.execute('${cli_test_support.command(false)} ./tests/cjs_runtime.cjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'cjs${os.path_separator}dep-ok\ntrue\ntrue'
}

fn test_cli_run_commonjs_shebang_and_json_file() {
	output := os.execute('${cli_test_support.command(false)} ./tests/cjs_shebang_runtime.cjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'json-ok'
}

fn test_cli_run_module_example() {
	output := os.execute('${cli_test_support.command(false)} --module ./examples/js/main.js')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'hello text\nfoo'
}

fn test_cli_run_with_script_runtime_profile() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime script ./tests/script_runtime_profile.mjs arg-one')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\nobject\nfunction\nundefined\narg-one\nexample.com'
}

fn test_cli_run_with_browser_runtime_profile() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./tests/browser_runtime_profile.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'object\nobject\nfunction\nfunction\nfunction\nobject\nfunction\nV大法好\n大\n07/15/2024, 14:30:45\nyear:2024|literal:/|month:07|literal:/|day:15|literal: |weekday:星期一\nundefined\nobject'
}

fn test_cli_browser_runtime_crypto_subtle_hmac() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./tests/browser_crypto_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'HMAC:SHA-256\nsecret\nfalse\nsign,verify\n32\ntrue\nfalse\ntrue\ntrue\nHMAC:SHA-512\n1024\ntrue\n128\n64\ntrue\nEd25519:Ed25519\npublic:private\ntrue:false\n64\ntrue\nfalse\n32\nEd25519:public\ntrue\nAES-CBC:128\n16\ntrue\ntrue\nAES-CTR:128\n5\ntrue\n16\nPBKDF2:secret\nae4d0c95af6b46d32d0adff928f06dd0\nAES-CBC:128\n16\nHMAC:SHA-512:256\n64\ntrue\nECDSA:P-256\npublic:private\ntrue\ntrue\nfalse\n65\n[object CryptoKey]\n[object SubtleCrypto]'
}

fn test_cli_browser_runtime_crypto_hmac_example() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./examples/webcrypto/hmac_sign_verify.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '32\ntrue'
}

fn test_cli_browser_runtime_crypto_aes_example() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./examples/webcrypto/aes_cbc_encrypt_decrypt.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '16\nhello'
}

fn test_cli_browser_runtime_crypto_pbkdf2_example() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./examples/webcrypto/pbkdf2_derive_aes.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'ae4d0c95af6b46d32d0adff928f06dd0\nAES-CBC:128'
}

fn test_cli_browser_runtime_crypto_signatures_example() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser --module ./examples/webcrypto/signatures.mjs')
	assert output.exit_code == 0
	lines := output.output.trim_space().split_into_lines()
	assert lines.len == 2
	assert lines[0] == 'Ed25519:64:true'
	assert lines[1] in ['ECDSA:70:true', 'ECDSA:71:true', 'ECDSA:72:true']
}

fn test_cli_browser_runtime_requires_module() {
	output :=
		os.execute('${cli_test_support.command(false)} --runtime browser ./tests/browser_runtime_profile.mjs')
	assert output.exit_code != 0
	assert output.output.contains('browser runtime requires module mode')
}

fn test_cli_rejects_unknown_runtime_profile() {
	output := os.execute('${cli_test_support.command(false)} --runtime hybrid ./tests/test.js')
	assert output.exit_code != 0
	assert output.output.contains('unknown runtime profile: hybrid')
}

fn test_cli_rejects_non_js_input() {
	output := os.execute('${cli_test_support.command(false)} --module ./tests/cli_runner_test.v')
	assert output.exit_code != 0
	assert output.output.contains('unsupported script type: ./tests/cli_runner_test.v')
}
