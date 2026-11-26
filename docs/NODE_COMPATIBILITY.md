# Node Compatibility

This document describes the Node-style builtin modules provided by the `node`
runtime profile. They are compatibility subsets designed for common packages;
they are not declarations that every Node.js API is implemented.

## Module Specifiers

The following filesystem specifiers resolve to the same host implementation:

| Specifier | Exports |
| --- | --- |
| `fs` | Asynchronous helpers, synchronous helpers, `watch()`, and the default export |
| `node:fs` | Alias of `fs` |
| `fs/promises` | Asynchronous helpers only |
| `node:fs/promises` | Alias of `fs/promises` |

The filesystem modules share `constants` for access checks and supported
open flags. `os.constants.signals` exposes common host signal numbers.
`path.win32` provides `join()` and `normalize()` on every platform.

The following crypto specifiers resolve to the same compatibility module:

| Specifier | Scope |
| --- | --- |
| `crypto` | Ed25519 operations, SHA-256/MD5 hashing, UUID generation, and Web Crypto accessors |
| `node:crypto` | Alias of `crypto` |

The full `node` profile also installs the Web Crypto globals `crypto`,
`crypto.subtle`, `CryptoKey`, and `SubtleCrypto`. The module exports
`webcrypto`, `subtle`, and `getRandomValues` as references to that same global
implementation.

`path`/`node:path`, `os`/`node:os`, and `zlib`/`node:zlib` are paired aliases.
The zlib subset currently exports `deflateRawSync()`.

`child_process` and `node:child_process` share the same exports and are
available when the policy allows subprocesses. `timers/promises` and
`node:timers/promises` expose the same promise-based `setTimeout()`.

These specifiers are also recognized as builtins by the TypeScript/runtime
module graph emitter, so they are not incorrectly resolved from
`node_modules` while bundling.

## Promise Filesystem API

The promise modules export:

- `readFile`
- `access`
- `writeFile`
- `appendFile`
- `exists`
- `mkdir`
- `mkdtemp`
- `readdir`
- `opendir`
- `open`
- `rm`
- `stat`
- `lstat`
- `statfs`
- `chmod`
- `copyFile`
- `rename`
- `realpath`
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

- `readFile()` resolves to a Buffer-compatible `Uint8Array` by default and to
  a string for the `utf8`/`utf-8` encoding.
- `writeFile()` and `writeFileSync()` preserve string, Buffer, TypedArray, and
  ArrayBuffer bytes. `readFileSync()` follows the same Buffer-by-default and
  UTF-8 encoding behavior as `readFile()`.
- The `w`, `w+`, `wx`, `xw`, `wx+`, and `xw+` write flags are supported.
  Exclusive variants use atomic creation and never degrade to truncating
  writes. Other flags are rejected.
- `mkdir()` creates missing parent directories.
- `rm()` accepts `{ recursive, force }` and the legacy boolean recursive flag.
- Operations run synchronously in the host and return an already settled
  JavaScript `Promise`.
- `statfs(path)` accepts string paths and returns filesystem metadata as
  Numbers. Set `{ bigint: true }` to receive exact BigInts. Windows reports
  zero for filesystem type and inode counts.
- `open()` supports `r`, `r+`, `w`, `wx`, and `a`. On Unix, numeric
  read-only flags can include `O_NONBLOCK` and `O_NOFOLLOW`. A file handle
  supports `read()`, `stat()`, `sync()`, `truncate()`, and `close()`.
- `readdir(path, { withFileTypes: true })` and `opendir()` expose directory
  entry names and type checks. An open directory reads from a snapshot.

Filesystem resolution remains governed by `NodeCompatConfig.fs_roots`. Relative
writes use the first configured root; relative reads try the provided path and
configured roots. Absolute paths are used as-is, and reads try a relative path
against the current working directory before configured roots. Consequently,
`fs_roots` is a resolution mechanism, not a filesystem sandbox. Do not expose
the filesystem modules to untrusted code without an additional host-level
policy boundary. For access boundaries, enable `HostPolicy.allow_fs_read` and/or
`allow_fs_write` and set `fs_read_roots`/`fs_write_roots`. See `SECURITY.md` for
canonicalization, symlink-race, and OS-sandbox limitations.

The direct `sqlite` compatibility module is omitted when bounded filesystem
roots are active because the driver does not enforce per-operation policy. The
same rule applies to `mysql` when a network hostname allowlist is active; use a
host-owned database API for bounded database access.

## Filesystem watching

`fs.watch(path, options?, listener?)` and `node:fs` watch string paths for
files or directories within the current filesystem read policy. The watcher
supports `recursive`, `persistent`, UTF-8 or buffer filenames, `AbortSignal`,
and the usual `on`, `once`, `off`, `close`, `ref`, and `unref` methods.

Watchers poll filesystem metadata every 100 ms and emit `change` or `rename`
for differences between snapshots. Multiple changes within one interval may
be coalesced or missed. Recursive scans do not traverse directory symlinks.
On the CLI, unreferenced watchers do not keep an idle process alive. An explicit
await can still receive their events. Managed hosts that own their timers
schedule watcher polls through their runtime scheduler.

## Node SQLite subset

With `-d vjsx_sqlite`, the trusted `node` profile also exposes
`node:sqlite`. It supports `new DatabaseSync(path, { readOnly, timeout })`,
`exec(sql)`, `prepare(sql)`, and `close()`. A statement supports
`run(...params)`, `get(...params)`, `all(...params)`, and
`setReadBigInts(enabled)`. `exec` accepts SQL scripts, including transaction
statements. `prepare` accepts a single statement and validates it before
returning a handle. The handle prepares the SQL again on each execution.

Positional bindings accept `null`, numbers, signed 64-bit bigints, strings, and
`Uint8Array` values. Reads preserve SQL `NULL`, integer, real, text, and blob
values. Integers outside JavaScript's safe range require
`setReadBigInts(true)`. `get` returns `undefined` if no row matches.
The existing `sqlite` module retains its string-oriented API. Both SQLite
modules require unrestricted filesystem read and write in the host policy.

## Raw DEFLATE API

`zlib` and `node:zlib` export `deflateRawSync()`. Compression is delegated to
V's `compress.deflate.compress_raw()` and the result is returned as a Buffer.
The default options and `{ level: 9 }` are accepted for the deterministic ZIP
use case. V's current stable raw-DEFLATE API does not expose tunable compression
levels, so other explicit levels are rejected rather than silently ignored.

## Ed25519 Crypto API

The crypto module exports:

- `KeyObject`
- `createHash()` (`sha256`/`sha-256` and `md5`)
- `createPrivateKey()`
- `createPublicKey()`
- `generateKeyPair()`
- `generateKeyPairSync()`
- `getRandomValues()`
- `randomUUID()`
- `sign()`
- `subtle`
- `verify()`
- `webcrypto`

`randomUUID()` obtains its 128 random bits from V's `crypto.rand` operating
system entropy source before applying the RFC 9562 version and variant bits.

### Web Crypto API

The full `node` profile exposes the same Web Crypto subset as the browser
profile. These identities hold:

```js
import { getRandomValues, subtle, webcrypto } from "node:crypto";

console.log(webcrypto === globalThis.crypto); // true
console.log(subtle === globalThis.crypto.subtle); // true
getRandomValues(new Uint8Array(16));
```

Current `SubtleCrypto` support includes:

| Area | Current support |
| --- | --- |
| `digest` | `SHA-1`, `SHA-256`, `SHA-384`, `SHA-512` |
| `HMAC` | `generateKey`, raw import/export, `sign`, `verify` |
| `AES-CBC` | `generateKey`, raw import/export, `encrypt`, `decrypt` |
| `AES-CTR` | `generateKey`, raw import/export, `encrypt`, `decrypt`; counter `length = 128` only |
| `PBKDF2` | raw base-key import, `deriveBits`, `deriveKey`; `SHA-256/384/512` |
| `Ed25519` | `generateKey`, `sign`, `verify`, raw public-key import/export |
| `ECDSA` | P-256/P-384/P-521 key generation, `sign`, `verify`, and raw/SPKI/PKCS8/JWK import/export |

`AES-GCM` is not implemented. Ed25519 and ECDSA raw export is limited to public
keys; ECDSA private keys use `pkcs8` or `jwk`.

ECDSA signatures use Web Crypto's fixed-width IEEE P1363 `r || s`
representation. P-256/ES256 signatures are therefore 64 bytes and can be
base64url encoded directly for JOSE and ACME.

ECDSA private keys are exportable and importable as PKCS8 or JWK when the
`CryptoKey` is extractable. Public keys support raw SEC1 points, SPKI, and JWK.
The executable compatibility test persists P-256 PKCS8/SPKI and JWK keys,
starts a new vjsx process, restores them, and completes 64-byte ES256
sign/verify round trips. These are the supported paths for durable vhttpd ACME
account keys.

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
| Public | SPKI or OKP JWK | PEM, DER, or JWK |

String and PEM Buffer input default to PEM. Binary DER input should use an
explicit descriptor:

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
string/Buffer, an explicit PKCS8 DER descriptor, or an OKP Ed25519 public JWK.

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
- RSA, DSA, ECDSA, X25519, and other algorithms through the Node-style
  `sign()`/`verify()` and `KeyObject` APIs (ECDSA is available only through
  `crypto.subtle` as documented above)
- PKCS1, SEC1, private JWK, certificates, and OpenSSH key containers
- streaming `Sign`/`Verify` objects
- hashes other than SHA-256 and MD5, HMAC, ciphers, KDFs, and the rest of the
  Node-style crypto surface (some equivalents are available through
  `crypto.subtle` as documented above)

The `node:crypto` module and global Web Crypto API are installed only by the
full Node-style compatibility profile. `node_compat_minimal()` and the `script`
profile do not install them.

## Native Fetch Transport

Global `fetch()` uses V's native HTTP client on background workers by default.
It no longer needs an external curl executable. The legacy Node `http.get()`
and `https.get()` modules are separate compatibility APIs and remain synchronous.

Workers receive only V-owned request data, a cancellation token, and a host-async
completion port. They never touch QuickJS. Responses and rejections are delivered
through the same completion queue as `RuntimeSession.start_host_async_operation()`.
The owner drains that queue using a short compatibility timer, so existing
`resolve_value()`, top-level await, and QuickJS timer-loop entrypoints keep working.
Configured `async_ready_fn` callbacks still receive completion notifications;
embedders may drive the queue through the managed session instead.

`FetchGlobalsConfig` controls the native transport:

- `max_concurrent_requests` defaults to 16 per installed fetch host. Excess
  requests reject immediately; zero disables native admission. There is no
  unbounded request queue.
- `timeout_ms` defaults to 30,000 and bounds the JS operation using monotonic
  time, including response buffering. Non-positive values select that default.
- `read_timeout` and `write_timeout` bound underlying V transport operations.
- Each native request makes one attempt. The legacy `max_retries` field is not
  used to automatically replay requests, including POST requests.
- `curl_proxy_fallback: true` explicitly selects the curl compatibility path
  when available. An explicit `curl_path` also selects it. Multipart requests
  always use the native transport. Native limits and `timeout_ms` do not apply
  to the curl path, which retains its existing read/write-derived timeout.

AbortSignal, native timeout, worker completion, and session close use the
host-async first-terminal-event gate. Cancellation promptly ends JS waiting,
but V's blocking HTTP API cannot immediately interrupt an in-flight socket or
DNS lookup. A cancelled worker retains its admission slot until its underlying
operation finishes; read/write timeouts still apply. The worker can safely
outlive the session because it owns no JS values. Late results are discarded.
This is asynchronous buffered HTTP, not incremental network-body streaming.

See `tests/fetch_transport_validation_test.v` for real local-server coverage of
parallel requests, timer progress, binary and multipart bodies, cancellation,
timeouts, bounded admission, recovery, and close during in-flight I/O.

## Capability Discovery

Use the CLI to check the selected runtime:

```sh
vjsx capabilities --runtime node
```

The module section reports `node:crypto`, `node:zlib`, `node:fs`, and
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
