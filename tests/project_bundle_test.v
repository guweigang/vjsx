import os
import runtimejs
import vjsx

fn test_project_bundle_transpiles_typescript_and_json_without_runtime_sources() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.mts'),
		'import { add } from "./dep.ts"; import data from "./data.json"; export const result = add(data.value, 2);') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'dep.ts'),
		'export function add(a: number, b: number): number { return a + b; }') or { panic(err) }
	os.write_file(os.join_path(root, 'data.json'), '{"value":40}') or { panic(err) }

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.mts'),
		app_name:        'typed-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }
	assert !os.exists(root)

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}

fn test_project_bundle_preserves_commonjs_require_and_exports() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_cjs_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.cjs'),
		'const helper = require("./helper.cjs"); module.exports = { result: helper.add(40, 2) };') or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'helper.cjs'),
		'module.exports = { add(a, b) { return a + b; } };') or { panic(err) }

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.cjs'),
		app_name:        'cjs-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}

fn test_project_bundle_includes_static_node_modules_dependencies() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_package_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	package_root := os.join_path(root, 'node_modules', 'answer-package')
	os.mkdir_all(package_root) or { panic(err) }
	os.write_file(os.join_path(root, 'main.mts'),
		'import { answer } from "answer-package"; export const result = answer;') or { panic(err) }
	os.write_file(os.join_path(package_root, 'package.json'),
		'{"name":"answer-package","version":"1.0.0","type":"module","exports":"./index.js"}') or {
		panic(err)
	}
	os.write_file(os.join_path(package_root, 'index.js'), 'export const answer = 42;') or {
		panic(err)
	}

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.mts'),
		app_name:        'package-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()
	os.rmdir_all(root) or { panic(err) }

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_int() == 42
}

fn test_project_bundle_strips_esm_shebang_and_resolves_node_builtin() {
	root := os.join_path(os.temp_dir(), 'vjsx_project_bundle_shebang_test_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'main.mjs'),
		'#!/usr/bin/env node\nimport { createHash, createPublicKey, generateKeyPairSync, randomUUID, verify } from "node:crypto";\nimport { homedir } from "node:os";\nimport { basename } from "node:path";\nimport { deflateRawSync } from "node:zlib";\nconst pair = generateKeyPairSync("ed25519");\nconst jwk = createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: "11qYAYdk9JqPtcDHoG1i3U7-VQK_mMSEh1DO_DuB5_Q" }, format: "jwk" });\nconst root = createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: "CeTgS9o/1Cb7MiXuFShi6deScYu2tg9hRwVLMEOfLEM=" }, format: "jwk" });\nconst rootPem = createPublicKey(Buffer.from("-----BEGIN PUBLIC KEY-----\\nMCowBQYDK2VwAyEACeTgS9o/1Cb7MiXuFShi6deScYu2tg9hRwVLMEOfLEM=\\n-----END PUBLIC KEY-----\\n"));\nconst payload = Buffer.from("eyJ0eXBlIjoiYWlkYXRhLnB1Ymxpc2hlci1jZXJ0aWZpY2F0ZSIsInNjaGVtYVZlcnNpb24iOjEsInNlcmlhbE51bWJlciI6ImIyMjc2NWVjLTBmMjktNGJiZS1hMjU4LTA2Nzg2MDAwMjA3MSIsInB1Ymxpc2hlcklkIjoiYWlkYXRhLW9mZmljaWFsIiwiZGlzcGxheU5hbWUiOiJBSSBEYXRhIFN0dWRpbyIsImtleUlkIjoib2ZmaWNpYWwtMjAyNi0wMSIsImFsZ29yaXRobSI6IkVkMjU1MTkiLCJwdWJsaWNLZXkiOiJ1R1o4UnBibjlLRjg5WjBrRTBuTEgxbkFLTGQza3pwWGpGVElYL2hMcCtnPSIsInBlcm1pc3Npb25zIjpbIndvcmtzcGFjZTpwdWJsaXNoIl0sImlzc3VlciI6ImFpZGF0YS1yb290LTIwMjYiLCJub3RCZWZvcmUiOiIyMDI2LTA4LTIyVDExOjQ1OjMzLjg1OFoiLCJpc3N1ZWRBdCI6IjIwMjYtMDgtMjJUMTE6NDU6MzMuODU4WiIsImV4cGlyZXNBdCI6IjIwMjgtMDgtMjFUMTE6NDU6MzMuODU4WiJ9", "base64");\nconst signatureBase64 = "+ZS2kPJdZqHVcpDM+kxpmHD8wZjkbUA7RPRyIVkGhdgpghniAHbLl7oDEHQj77mCFeutco+K/gD8gvjk5FMMCA==";\nconst signature = Buffer.from(signatureBase64, "base64");\nconst binarySignature = atob(signatureBase64);\nconst header = Buffer.alloc(4); header.writeUInt32LE(0x04034b50);\nconst compressed = deflateRawSync(Buffer.from("hello"));\nexport const result = pair.publicKey.type + ":" + typeof homedir() + ":" + basename("/tmp/demo") + ":" + header.toString("hex") + ":" + compressed.length + ":" + createHash("sha256").update("abc").digest("hex") + ":" + createHash("md5").update("abc").digest("hex") + ":" + jwk.type + ":" + randomUUID().length + ":" + signature.length + ":" + binarySignature.length + ":" + binarySignature.charCodeAt(0) + ":" + verify(null, payload, root, signature) + ":" + verify(null, payload, rootPem, signature);') or {
		panic(err)
	}

	mut compiler := vjsx.new_runtime_session()
	bundle := runtimejs.compile_project_bundle(compiler.context(), os.join_path(root, 'main.mjs'),
		app_name:        'esm-shebang-demo'
		runtime_profile: 'node'
	) or { panic(err) }
	compiler.close()

	mut runtime := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{})
	defer {
		runtime.close()
	}
	mut app := runtime.context().load_bundle(bundle) or { panic(err) }
	defer {
		app.close()
	}
	result := app.get('result') or { panic(err) }
	defer {
		result.free()
	}
	assert result.to_string() == 'public:string:demo:504b0304:7:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad:900150983cd24fb0d6963f7d28e17f72:public:36:64:64:249:true:true'
}
