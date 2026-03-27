module runtimejs

import rand
import vjsx
import crypto.aes
import crypto.cipher
import crypto.ecdsa
import crypto.ed25519
import crypto.hmac
import crypto.pbkdf2
import crypto.sha1
import crypto.sha256
import crypto.sha512

fn cli_browser_sha1_hash(data []u8) []u8 {
	return sha1.sum(data)
}

fn cli_browser_sha256_hash(data []u8) []u8 {
	return sha256.sum256(data)
}

fn cli_browser_sha384_hash(data []u8) []u8 {
	return sha512.sum384(data)
}

fn cli_browser_sha512_hash(data []u8) []u8 {
	return sha512.sum512(data)
}

fn cli_browser_pbkdf2_sha256(password []u8, salt []u8, iterations int, key_length int) []u8 {
	return pbkdf2.key(password, salt, iterations, key_length, sha256.new()) or { panic(err) }
}

fn cli_browser_pbkdf2_sha384(password []u8, salt []u8, iterations int, key_length int) []u8 {
	return pbkdf2.key(password, salt, iterations, key_length, sha512.new384()) or { panic(err) }
}

fn cli_browser_pbkdf2_sha512(password []u8, salt []u8, iterations int, key_length int) []u8 {
	return pbkdf2.key(password, salt, iterations, key_length, sha512.new()) or { panic(err) }
}

fn cli_browser_ecdsa_nid_from_curve_name(name string) ecdsa.Nid {
	match name {
		'P-256' { return .prime256v1 }
		'P-384' { return .secp384r1 }
		'P-521' { return .secp521r1 }
		else { panic('unsupported ECDSA named curve: ${name}') }
	}
}

fn cli_browser_ecdsa_signer_opts_from_hash_name(name string) ecdsa.SignerOpts {
	match name {
		'SHA-1' {
			return ecdsa.SignerOpts{
				hash_config:        .with_custom_hash
				allow_custom_hash:  true
				allow_smaller_size: true
				custom_hash:        sha1.new()
			}
		}
		'SHA-256' {
			return ecdsa.SignerOpts{
				hash_config:        .with_custom_hash
				allow_custom_hash:  true
				allow_smaller_size: true
				custom_hash:        sha256.new()
			}
		}
		'SHA-384' {
			return ecdsa.SignerOpts{
				hash_config:        .with_custom_hash
				allow_custom_hash:  true
				allow_smaller_size: true
				custom_hash:        sha512.new384()
			}
		}
		'SHA-512' {
			return ecdsa.SignerOpts{
				hash_config:        .with_custom_hash
				allow_custom_hash:  true
				allow_smaller_size: true
				custom_hash:        sha512.new()
			}
		}
		else {
			panic('unsupported ECDSA hash: ${name}')
		}
	}
}

fn cli_browser_crypto_boot(ctx &vjsx.Context, boot vjsx.Value) {
	obj := ctx.js_object()
	obj.set('rand_uuid', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_string(rand.uuid_v4())
	}))
	obj.set('rand_bytes', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		bytes := rand.bytes(args[0].to_int()) or { panic(err) }
		return ctx.js_array_buffer(bytes)
	}))
	obj.set('digest_sha1', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := sha1.sum(args[0].to_bytes())
		return ctx.js_array_buffer(sum)
	}))
	obj.set('digest_sha256', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := sha256.sum256(args[0].to_bytes())
		return ctx.js_array_buffer(sum)
	}))
	obj.set('digest_sha384', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := sha512.sum384(args[0].to_bytes())
		return ctx.js_array_buffer(sum)
	}))
	obj.set('digest_sha512', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := sha512.sum512(args[0].to_bytes())
		return ctx.js_array_buffer(sum)
	}))
	obj.set('hmac_sha1', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := hmac.new(args[0].to_bytes(), args[1].to_bytes(), cli_browser_sha1_hash,
			sha1.block_size)
		return ctx.js_array_buffer(sum)
	}))
	obj.set('hmac_sha256', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := hmac.new(args[0].to_bytes(), args[1].to_bytes(), cli_browser_sha256_hash,
			sha256.block_size)
		return ctx.js_array_buffer(sum)
	}))
	obj.set('hmac_sha384', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := hmac.new(args[0].to_bytes(), args[1].to_bytes(), cli_browser_sha384_hash,
			sha512.block_size)
		return ctx.js_array_buffer(sum)
	}))
	obj.set('hmac_sha512', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		sum := hmac.new(args[0].to_bytes(), args[1].to_bytes(), cli_browser_sha512_hash,
			sha512.block_size)
		return ctx.js_array_buffer(sum)
	}))
	obj.set('timing_safe_equal', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_bool(hmac.equal(args[0].to_bytes(), args[1].to_bytes()))
	}))
	obj.set('ed25519_generate_key', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		publickey, privatekey := ed25519.generate_key() or { panic(err) }
		pair := ctx.js_object()
		pair.set('publicKey', ctx.js_array_buffer(publickey))
		pair.set('privateKey', ctx.js_array_buffer(privatekey))
		return pair
	}))
	obj.set('ed25519_public_from_private', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		privatekey := ed25519.PrivateKey(args[0].to_bytes())
		return ctx.js_array_buffer(privatekey.public_key())
	}))
	obj.set('ed25519_sign', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		privatekey := ed25519.PrivateKey(args[0].to_bytes())
		signature := ed25519.sign(privatekey, args[1].to_bytes()) or { panic(err) }
		return ctx.js_array_buffer(signature)
	}))
	obj.set('ed25519_verify', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		publickey := ed25519.PublicKey(args[0].to_bytes())
		valid := ed25519.verify(publickey, args[1].to_bytes(), args[2].to_bytes()) or {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(valid)
	}))
	obj.set('aes_cbc_encrypt', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		block := aes.new_cipher(args[0].to_bytes())
		mut mode := cipher.new_cbc(block, args[2].to_bytes())
		mut out := []u8{len: args[1].byte_len()}
		mode.encrypt_blocks(mut out, args[1].to_bytes())
		return ctx.js_array_buffer(out)
	}))
	obj.set('aes_cbc_decrypt', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		block := aes.new_cipher(args[0].to_bytes())
		mut mode := cipher.new_cbc(block, args[2].to_bytes())
		mut out := []u8{len: args[1].byte_len()}
		mode.decrypt_blocks(mut out, args[1].to_bytes())
		return ctx.js_array_buffer(out)
	}))
	obj.set('aes_ctr_xor', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		block := aes.new_cipher(args[0].to_bytes())
		mut stream := cipher.new_ctr(block, args[2].to_bytes())
		mut out := []u8{len: args[1].byte_len()}
		stream.xor_key_stream(mut out, args[1].to_bytes())
		return ctx.js_array_buffer(out)
	}))
	obj.set('pbkdf2_sha256', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_array_buffer(cli_browser_pbkdf2_sha256(args[0].to_bytes(), args[1].to_bytes(),
			args[2].to_int(), args[3].to_int()))
	}))
	obj.set('pbkdf2_sha384', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_array_buffer(cli_browser_pbkdf2_sha384(args[0].to_bytes(), args[1].to_bytes(),
			args[2].to_int(), args[3].to_int()))
	}))
	obj.set('pbkdf2_sha512', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		return ctx.js_array_buffer(cli_browser_pbkdf2_sha512(args[0].to_bytes(), args[1].to_bytes(),
			args[2].to_int(), args[3].to_int()))
	}))
	obj.set('ecdsa_generate_key', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		nid := cli_browser_ecdsa_nid_from_curve_name(args[0].to_string())
		publickey, privatekey := ecdsa.generate_key(nid: nid) or { panic(err) }
		pub_bytes := publickey.bytes() or { panic(err) }
		priv_bytes := privatekey.bytes() or { panic(err) }
		pair := ctx.js_object()
		pair.set('publicKey', ctx.js_array_buffer(pub_bytes))
		pair.set('privateKey', ctx.js_array_buffer(priv_bytes))
		publickey.free()
		privatekey.free()
		return pair
	}))
	obj.set('ecdsa_public_from_private', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		nid := cli_browser_ecdsa_nid_from_curve_name(args[1].to_string())
		privatekey := ecdsa.new_key_from_seed(args[0].to_bytes(), nid: nid) or { panic(err) }
		publickey := privatekey.public_key() or { panic(err) }
		pub_bytes := publickey.bytes() or { panic(err) }
		publickey.free()
		privatekey.free()
		return ctx.js_array_buffer(pub_bytes)
	}))
	obj.set('ecdsa_sign', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		nid := cli_browser_ecdsa_nid_from_curve_name(args[2].to_string())
		opt := cli_browser_ecdsa_signer_opts_from_hash_name(args[3].to_string())
		privatekey := ecdsa.new_key_from_seed(args[0].to_bytes(), nid: nid) or { panic(err) }
		signature := privatekey.sign(args[1].to_bytes(), opt) or { panic(err) }
		privatekey.free()
		return ctx.js_array_buffer(signature)
	}))
	obj.set('ecdsa_verify_with_private', ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
		nid := cli_browser_ecdsa_nid_from_curve_name(args[3].to_string())
		opt := cli_browser_ecdsa_signer_opts_from_hash_name(args[4].to_string())
		privatekey := ecdsa.new_key_from_seed(args[0].to_bytes(), nid: nid) or {
			return ctx.js_bool(false)
		}
		publickey := privatekey.public_key() or {
			privatekey.free()
			return ctx.js_bool(false)
		}
		valid := publickey.verify(args[1].to_bytes(), args[2].to_bytes(), opt) or { false }
		publickey.free()
		privatekey.free()
		return ctx.js_bool(valid)
	}))
	boot.set('crypto', obj)
}
