module vjsx

import crypto.ed25519
import crypto.md5
import crypto.sha256

// Install the practical Ed25519 subset of Node's `crypto`/`node:crypto`
// modules. The JS compatibility layer owns KeyObject and RFC 8410 DER/PEM
// handling; these callbacks keep private-key operations in V.
pub fn (ctx &Context) install_node_crypto_module() {
	glob, boot := fetch_get_bootstrap(ctx)
	native := ctx.js_object()
	native.set('digest', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len < 2 {
			return ctx.js_throw(ctx.js_error(
				message: 'algorithm and data are required'
				name:    'TypeError'
			))
		}
		bytes := args[1].to_bytes()
		digest := match args[0].str().to_lower() {
			'sha256', 'sha-256' {
				sha256.sum(bytes)
			}
			'md5' {
				md5.sum(bytes)
			}
			else {
				return ctx.js_throw(ctx.js_error(
					message: 'Digest method not supported: ${args[0].str()}'
					name:    'TypeError'
				))
			}
		}
		return ctx.js_array_buffer(digest)
	}))
	native.set('randomUUID', ctx.js_function(fn [ctx] (args []Value) Value {
		uuid := secure_random_uuid_v4() or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
		return ctx.js_string(uuid)
	}))
	native.set('generateKey', ctx.js_function(fn [ctx] (args []Value) Value {
		public_key, private_key := ed25519.generate_key() or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		pair := ctx.js_object()
		pair.set('publicKey', ctx.js_array_buffer(public_key))
		pair.set('privateKey', ctx.js_array_buffer(private_key))
		return pair
	}))
	native.set('privateFromSeed', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 || args[0].byte_len() != ed25519.seed_size {
			return ctx.js_throw(ctx.js_error(
				message: 'Ed25519 private key seed must be 32 bytes'
				name:    'TypeError'
			))
		}
		private_key := ed25519.new_key_from_seed(args[0].to_bytes())
		return ctx.js_array_buffer(private_key)
	}))
	native.set('publicFromPrivate', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len == 0 || args[0].byte_len() != ed25519.private_key_size {
			return ctx.js_throw(ctx.js_error(
				message: 'Ed25519 private key must be 64 bytes'
				name:    'TypeError'
			))
		}
		private_key := ed25519.PrivateKey(args[0].to_bytes())
		return ctx.js_array_buffer(private_key.public_key())
	}))
	native.set('sign', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len < 2 || args[0].byte_len() != ed25519.private_key_size {
			return ctx.js_throw(ctx.js_error(
				message: 'Ed25519 signing requires a 64-byte private key'
				name:    'TypeError'
			))
		}
		signature := ed25519.sign(ed25519.PrivateKey(args[0].to_bytes()), args[1].to_bytes()) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		return ctx.js_array_buffer(signature)
	}))
	native.set('verify', ctx.js_function(fn [ctx] (args []Value) Value {
		if args.len < 3 || args[0].byte_len() != ed25519.public_key_size {
			return ctx.js_bool(false)
		}
		valid := ed25519.verify(ed25519.PublicKey(args[0].to_bytes()), args[1].to_bytes(),
			args[2].to_bytes()) or { false }
		return ctx.js_bool(valid)
	}))
	boot.set('nodeCrypto', native)
	native.free()
	ctx.eval_runtime_file('web/js/node_crypto.js', type_module) or { panic(err) }

	helpers := ctx.js_global('__vjsxNodeCrypto')
	export_names := ['KeyObject', 'createHash', 'createPrivateKey', 'createPublicKey',
		'generateKeyPair', 'generateKeyPairSync', 'randomUUID', 'sign', 'verify']
	for module_name in ['crypto', 'node:crypto'] {
		mut crypto_mod := ctx.js_module(module_name)
		default_obj := ctx.js_object()
		for name in export_names {
			value := helpers.get(name)
			crypto_mod.export(name, value)
			default_obj.set(name, value)
			value.free()
		}
		crypto_mod.export_default(default_obj)
		crypto_mod.create()
		default_obj.free()
	}
	glob.delete('__bootstrap')
	boot.free()
	helpers.free()
	glob.free()
}
