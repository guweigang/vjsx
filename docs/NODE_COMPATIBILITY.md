# Node Compatibility

This document describes the Node-style builtin modules provided by the `node`
runtime profile. They are compatibility subsets designed for common packages;
they are not declarations that every Node.js API is implemented.

## Module Specifiers

The following filesystem specifiers resolve to the same host implementation:

| Specifier | Exports |
| --- | --- |
| `fs` | Asynchronous helpers, synchronous helpers, and the default export |
| `node:fs` | Alias of `fs` |
| `fs/promises` | Asynchronous helpers only |
| `node:fs/promises` | Alias of `fs/promises` |

The following crypto specifiers resolve to the same Ed25519 implementation:

| Specifier | Scope |
| --- | --- |
| `crypto` | Ed25519 key import/export, generation, signing, and verification |
| `node:crypto` | Alias of `crypto` |

These specifiers are also recognized as builtins by the TypeScript/runtime
module graph emitter, so they are not incorrectly resolved from
`node_modules` while bundling.

## Promise Filesystem API

The promise modules export:

- `readFile`
- `writeFile`
- `exists`
- `mkdir`
- `readdir`
- `rm`
- `stat`
- `copyFile`
- `rename`
- `readJson`
- `writeJson`

Example:

```js
import { mkdir, readFile, writeFile } from "node:fs/promises";

await mkdir("./data");
await writeFile("./data/message.txt", "hello");
console.log(await readFile("./data/message.txt"));
```

The current behavior intentionally follows the existing vjsx filesystem host:

- `readFile()` resolves to a string, including when no encoding is provided.
- `writeFile()` writes the string representation of its data argument.
- `mkdir()` creates missing parent directories.
- `rm(path, recursive)` accepts a boolean recursive flag rather than Node's
  complete options object.
- Operations execute through V's filesystem functions and return an already
  settled or rejected JavaScript `Promise`; they are not backed by Node's
  libuv worker pool.
- `FileHandle`, `open()`, streams in the promise module, `AbortSignal`, flags,
  encoding options, and the complete Node error-code surface are not yet
  implemented.

Filesystem resolution remains governed by `NodeCompatConfig.fs_roots`. Relative
writes use the first configured root; relative reads try the provided path and
configured roots. Absolute paths are used as-is, and reads try a relative path
against the current working directory before configured roots. Consequently,
`fs_roots` is a resolution mechanism, not a filesystem sandbox. Do not expose
the filesystem modules to untrusted code without an additional host-level
policy boundary.

## Ed25519 Crypto API

The crypto module exports:

- `KeyObject`
- `createPrivateKey()`
- `createPublicKey()`
- `generateKeyPair()`
- `generateKeyPairSync()`
- `sign()`
- `verify()`

### Import, sign, and verify

```js
import {
  createPrivateKey,
  createPublicKey,
  sign,
  verify,
} from "node:crypto";

const privateKey = createPrivateKey(process.env.ED25519_PRIVATE_KEY_PEM);
const publicKey = createPublicKey(privateKey);
const message = new TextEncoder().encode("signed by vjsx");
const signature = sign(null, message, privateKey);

console.log(verify(null, message, publicKey, signature));
```

Ed25519 follows Node's rule that the algorithm passed to `sign()` and
`verify()` must be `null` or `undefined`.

### Supported key formats

| Key | Container | Encoding |
| --- | --- | --- |
| Private | PKCS8 | PEM or DER |
| Public | SPKI | PEM or DER |

String input defaults to PEM. Binary input should use an explicit descriptor:

```js
const privateKey = createPrivateKey({
  key: privateKeyDer,
  format: "der",
  type: "pkcs8",
});

const publicKey = createPublicKey({
  key: publicKeyDer,
  format: "der",
  type: "spki",
});
```

`createPublicKey()` also accepts an Ed25519 private `KeyObject`, a PKCS8 PEM
string, or an explicit PKCS8 DER descriptor and derives the matching public
key.

### Key generation and export

```js
import { generateKeyPairSync } from "node:crypto";

const { publicKey, privateKey } = generateKeyPairSync("ed25519");

const privatePem = privateKey.export({ format: "pem", type: "pkcs8" });
const publicPem = publicKey.export({ format: "pem", type: "spki" });
```

The callback API is also available:

```js
import { generateKeyPair } from "node:crypto";

generateKeyPair("ed25519", (error, publicKey, privateKey) => {
  if (error) throw error;
  // use publicKey/privateKey
});
```

Generation options may contain `publicKeyEncoding` and `privateKeyEncoding` to
return encoded keys directly, matching the common Node.js calling convention.

### Crypto boundaries

The implementation uses V's pure `crypto.ed25519` primitives. The JS
compatibility layer implements the RFC 8410 PKCS8/SPKI structures and validates
DER tags, canonical lengths, the Ed25519 OID, key sizes, bit-string padding,
and trailing data.

The following are intentionally unsupported and rejected:

- encrypted PKCS8 and passphrases
- RSA, DSA, ECDSA, X25519, and other algorithms through `node:crypto`
- PKCS1, SEC1, JWK, certificates, and OpenSSH key containers
- streaming `Sign`/`Verify` objects
- hashing, HMAC, ciphers, KDFs, and the rest of the full Node crypto surface

Browser-profile applications should continue using `crypto.subtle`; the
`node:crypto` module is installed only by the full Node-style compatibility
profile. `node_compat_minimal()` and the `script` profile do not install it.

## Capability Discovery

Use the CLI to check the selected runtime:

```sh
vjsx capabilities --runtime node
```

The module section reports `node:crypto`, `node:fs`, and
`node:fs/promises`. Embedders can inspect the corresponding fields on
`RuntimeProfileSnapshot`.

## Interoperability Tests

The compatibility test uses a deterministic PKCS8 Ed25519 key and compares the
derived SPKI public key and signature with Node.js output. It also covers both
bare and `node:` imports, synchronous and callback key generation, PEM/DER
export, verification failure, malformed DER rejection, and promise filesystem
read/write/remove behavior.

See
[`tests/host_node_compat_modules_runtime.mjs`](../tests/host_node_compat_modules_runtime.mjs)
for the executable contract.
