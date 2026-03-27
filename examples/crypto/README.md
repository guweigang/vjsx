# Crypto Examples

Run these examples with the browser-style runtime profile:

```bash
./vjsx --runtime browser --module ./examples/crypto/<file>.mjs
```

## Files

### `hmac_sign_verify.mjs`

Imports a raw HMAC key, signs `"hello"`, then verifies the signature.

Expected output:

```text
32
true
```

### `aes_cbc_encrypt_decrypt.mjs`

Imports a raw AES-CBC key, encrypts `"hello"`, then decrypts it again.

Expected output:

```text
16
hello
```

### `pbkdf2_derive_aes.mjs`

Imports a raw password as a PBKDF2 base key, derives bits, then derives an
AES-CBC key.

Expected output:

```text
ae4d0c95af6b46d32d0adff928f06dd0
AES-CBC:128
```

### `signatures.mjs`

Generates an Ed25519 key pair and an ECDSA P-256 key pair, then signs and
verifies `"hello"` with both.

Expected output:

```text
Ed25519:64:true
ECDSA:71:true
```

Note: the ECDSA signature length depends on DER encoding details and may vary
across implementations. In this repository's current runtime it is `71` bytes.
