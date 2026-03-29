# VJSX

<p align="center">
  <img src="assets/vjsx_brand.jpg" alt="VJSX brand" width="720" />
</p>

[V](https://vlang.io/) bindings to [QuickJS](https://bellard.org/quickjs/)
javascript engine. Run JS in V.

The first version of this project was derived from
[herudi/vjs](https://github.com/herudi/vjs). Thanks to the original author for
the foundational work that helped kick off `vjsx`.

## Features

- Evaluate js (code, file, module, etc).
- Multi evaluate support.
- Callback function support.
- Set-Globals support.
- Set-Module support.
- Call V from JS.
- Call JS from V.
- Top-Level `await` support. using `vjsx.type_module`.

## Install

```bash
v install vjsx
```

## Build With Local QuickJS Source

If you already have a local QuickJS checkout, you can compile `vjsx` against the
source tree directly instead of the bundled prebuilt archives.

This is useful when:

- you are on an unsupported architecture such as `macOS arm64`
- you want to use a newer QuickJS version
- you do not want to maintain extra prebuilt `.a` files inside this repo

Example:

```bash
VJS_QUICKJS_PATH=/Users/guweigang/Source/quickjs \
v -d build_quickjs run main.v
```

Notes:

- `VJS_QUICKJS_PATH` should point to the QuickJS source root that contains
  `quickjs.c`, `quickjs-libc.c`, `quickjs.h`, and `quickjs-libc.h`.
- In this mode `vjsx` compiles QuickJS C sources directly.
- Without `-d build_quickjs`, `vjsx` uses the bundled headers under
  `libs/include/` together with the prebuilt archives in `libs/`.

## Basic Usage

Create file `main.v` and copy-paste this code.

```v
import vjsx

fn main() {
  mut session := vjsx.new_runtime_session()
  defer {
    session.close()
  }
  ctx := session.context()

  value := ctx.eval('1 + 2') or { panic(err) }
  ctx.end()
  defer {
    value.free()
  }

  assert value.is_number() == true
  assert value.is_string() == false
  assert value.to_int() == 3

  println(value)
  // 3
}
```

## Run

```bash
v run main.v
```

With a local QuickJS checkout:

```bash
VJS_QUICKJS_PATH=/Users/guweigang/Source/quickjs \
v -d build_quickjs run main.v
```

Explore [examples](https://github.com/guweigang/vjsx/tree/master/examples)

If you want the smallest file-based example, see
`examples/run_file.v` together with `examples/js/foo.js`.

## CLI

You can also run JS files directly from the repository:

```bash
./vjsx ./tests/test.js
```

Module mode:

```bash
./vjsx --module ./examples/js/main.js
```

TypeScript entry files are also supported:

```bash
./vjsx ./tests/ts_basic.ts
./vjsx --module ./tests/ts_module_runtime.mts
```

TypeScript module graphs are also supported, including:

- relative `.ts` / `.mts` imports
- nearest `tsconfig.json`, including `extends`
- `compilerOptions.baseUrl` and `paths`
- bare package imports resolved from local `node_modules`
- package `exports` root and explicit subpath entries

Options:

- `--module`, `-m`: run the file as an ES module

This is runtime transpilation backed by the bundled `typescript.js`, and the
same loader is now also available from the `vjsx` API through
`ctx.install_typescript_runtime()` and `ctx.run_runtime_entry(...)`.
It is a good fit for standalone `.ts` scripts, `.mts` modules, and small local
module graphs. Project-wide features like full `tsc` diagnostics, `references`,
and broader Node compatibility are still out of scope for now.

When embedding `vjsx` in a long-lived process, always pair each created
`Runtime`/`Context` with an explicit `free()`. Repeated TypeScript bootstrap
work in the same process assumes those runtimes are torn down deliberately;
leaking them can surface later as hard-to-diagnose bootstrap failures.

If you want one owner object for embedded use, prefer `vjsx.new_runtime_session()`
and `session.close()`, which tear down the `Context` and `Runtime` together.
For Node-style hosts, that teardown also closes tracked `sqlite` / `mysql`
connections that were left open by JS code.

`vjsx.new_runtime()` and `rt.new_context()` are still available for advanced
manual ownership cases, but then the caller is responsible for pairing them
with `ctx.free()` and `rt.free()` correctly.

The wrapper script will use `VJS_QUICKJS_PATH` when it is set. If it is not
set, it will try `../quickjs` relative to the repository root as a local
convenience fallback.

> Currently support linux/mac/win (x64).

> in windows, requires `-cc gcc`.

## Host Profiles

The runtime is now split into clearer layers:

- `ctx.install_runtime_globals(...)`: reusable globals like `Buffer`, timers,
  `URL`, and `URLPattern`
- `ctx.install_node_compat(...)`: Node-like host features such as `console`,
  `fs`, `path`, `process`, `sqlite`, and optional `mysql`
- `web.inject_browser_host(ctx, ...)`: browser-style host features under
  `web/`, including `window`, DOM bootstrap, and Web APIs

`web.inject_browser_host(...)` is now configurable, so you can expose only the
browser-facing modules you want, while still letting higher-level features like
`fetch` pull in their required Web API dependencies.

The legacy `ctx.install_host(...)` entrypoint still works as a compatibility
wrapper around `install_node_compat(...)`.

Database host modules:

- `import { open } from "sqlite"` is available in the default Node-style host
  profile
- `import { connect } from "mysql"` is also exposed, but the real V MySQL
  backend is only compiled when you pass `-d vjsx_mysql`
- The CLI forwards extra V compiler flags through `VJS_V_FLAGS`, for example:
  `VJS_V_FLAGS='-d vjsx_mysql' ./vjsx --module app.mjs`
- End-to-end example files live under `examples/db/`

SQLite example:

```js
import { open } from "sqlite";

const db = await open({ path: "./app.db", busyTimeout: 1000 });
await db.exec("create table if not exists users (id integer primary key, name text)");
await db.execMany("insert into users(name) values (?)", [["alice"], ["bob"]]);
const firstUser = await db.queryOne("select id, name from users order by id");
const userCount = await db.scalar("select count(*) from users");
console.log(firstUser ? firstUser.name : "null", userCount);
await db.close();
```

MySQL example:

```js
import { connect } from "mysql";

const db = await connect({
  host: "127.0.0.1",
  port: 3306,
  user: "root",
  password: "",
  database: "mysql",
});
const stmt = await db.prepareCached("select id, name from users where name <> ? order by id");
const rows = await stmt.query(["carol"]);
console.log(rows.length);
await stmt.close();
await db.close();
```

DB host API shape:

- `sqlite.open({ path, busyTimeout? })`
- `mysql.connect({ host?, port?, user?|username?, password?, database?|dbname? })`
- `db.query(sql, params?)`
- `db.queryOne(sql, params?)`
- `db.scalar(sql, params?)`
- `db.queryMany(sql, [[...], [...]])`
- `db.exec(sql, params?)`
- `db.execMany(sql, [[...], [...]])`
- `await db.prepareCached(sql)` reuses the same prepared statement for repeated
  SQL text until that statement is closed
- `stmt.close()` and `db.close()` are idempotent, and `db.close()` also marks
  cached/reusable statements as closed
- `db.begin()`
- `db.commit()`
- `db.rollback()`
- `db.transaction(async (tx) => { ... })`
- `await db.prepare(sql)` returning a reusable statement with `query(params?)`,
  `queryOne(params?)`, `scalar(params?)`, `queryMany([[...], [...]])`,
  `exec(params?)`, `execMany([[...], [...]])`, and `close()`
- `db.close()`
- `mysql` connections also expose `db.ping()`
- `db.driver` identifies the backend, for example `sqlite` or `mysql`
- `db.supportsTransactions` tells you whether transaction helpers are available
- `db.inTransaction` reflects the host connection's current transaction state
- `db.toString()` and `stmt.toString()` provide compact debug-friendly summaries
- `db.exec(...)` returns `rows`, `changes`, `rowsAffected`, `lastInsertRowid`,
  and `insertId`

`process.env` is exposed as a live host view, so reads reflect environment
variable changes made by the embedding process after the runtime was installed.
- statements expose `driver`, `supportsTransactions`, `sql`, `kind`, and `closed`

When `params` are provided to `mysql.query(...)` or `mysql.exec(...)`, vjsx
now routes them through V's prepared statement support instead of expanding SQL
placeholders in user space.

For lifecycle-sensitive code, cached statements are scoped to the connection:
`prepareCached(...)` returns the same statement for repeated SQL text until that
statement is closed, and `db.close()` marks all cached/reusable statements as
closed.

For local or CI integration tests against a live MySQL server, the optional
`tests/host_mysql_runtime_test.v` probe reads `VJS_TEST_MYSQL_HOST`,
`VJS_TEST_MYSQL_PORT`, `VJS_TEST_MYSQL_USER`, `VJS_TEST_MYSQL_PASSWORD`,
`VJS_TEST_MYSQL_DBNAME`, and `VJS_TEST_MYSQL_TABLE`.

Useful presets:

- `vjsx.runtime_globals_full()`
- `vjsx.runtime_globals_minimal()`
- `vjsx.node_compat_full(fs_roots, process_args)`
- `vjsx.node_compat_minimal(fs_roots, process_args)`
- `web.browser_host_full()`
- `web.browser_host_minimal()`

Higher-level runtime entrypoints:

- `ctx.install_script_runtime(...)`
- `ctx.install_node_runtime(...)`
- `web.inject_browser_runtime(ctx)`
- `web.inject_browser_runtime_minimal(ctx)`

CLI runtime profiles:

- `./vjsx --runtime node ...`
- `./vjsx --runtime script ...`
- `./vjsx --runtime browser --module ...`

The CLI defaults to `--runtime node` for backwards compatibility.
`browser` is intentionally a pure browser-style host profile and currently
requires `--module`. The current CLI browser profile exposes browser-like
globals such as `window`, `self`, `EventTarget`, `URL`, timers, streams,
`Blob`, and `FormData`, while intentionally leaving out Node globals like
`process`, `Buffer`, and modules such as `fs`.

Example:

```v
import vjsx
import herudi.vjsx.web

fn main() {
  mut session := vjsx.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
    process_args: ['inline.js']
  })
  defer {
    session.close()
  }
  ctx := session.context()

  web.inject_browser_runtime_minimal(ctx)
}
```

## Multi Evaluate

```v
ctx.eval('const sum = (a, b) => a + b') or { panic(err) }
ctx.eval('const mul = (a, b) => a * b') or { panic(err) }

sum := ctx.eval('sum(${1}, ${2})') or { panic(err) }
mul := ctx.eval('mul(${1}, ${2})') or { panic(err) }

ctx.end()

println(sum)
// 3

println(mul)
// 2
```

## Add Global

```v
glob := ctx.js_global()
glob.set('foo', 'bar')

value := ctx.eval('foo') or { panic(err) }
ctx.end()

println(value)
// bar
```

## Add Module

```v
mut mod := ctx.js_module('my-module')
mod.export('foo', 'foo')
mod.export('bar', 'bar')
mod.export_default(mod.to_object())
mod.create()

code := '
  import mod, { foo, bar } from "my-module";

  console.log(foo, bar);

  console.log(mod);
'

ctx.eval(code, vjsx.type_module) or { panic(err) }
ctx.end()
```

## Web Platform APIs

Inject Web API to vjsx.

```v
import vjsx
import herudi.vjsx.web

fn main() {
  mut session := vjsx.new_runtime_session()
  defer {
    session.close()
  }
  ctx := session.context()

  // inject all browser host features
  web.inject_browser_host(ctx)

  // or inject one by one
  // web.console_api(ctx)
  // web.encoding_api(ctx)
  // more..

  ...
}
```
### List Web Platform APIs
- [x] [Console](https://developer.mozilla.org/en-US/docs/Web/API/console)
- [x] [setTimeout](https://developer.mozilla.org/en-US/docs/Web/API/setTimeout),
      [clearTimeout](https://developer.mozilla.org/en-US/docs/Web/API/clearTimeout)
- [x] [setInterval](https://developer.mozilla.org/en-US/docs/Web/API/setInterval),
      [clearInterval](https://developer.mozilla.org/en-US/docs/Web/API/clearInterval)
- [x] [btoa](https://developer.mozilla.org/en-US/docs/Web/API/btoa),
      [atob](https://developer.mozilla.org/en-US/docs/Web/API/atob)
- [x] [URL](https://developer.mozilla.org/en-US/docs/Web/API/URL)
- [x] [URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
- [x] [URLPattern](https://developer.mozilla.org/en-US/docs/Web/API/URLPattern)
- [x] [Encoding API](https://developer.mozilla.org/en-US/docs/Web/API/Encoding_API)
  - [x] [TextEncoder](https://developer.mozilla.org/en-US/docs/Web/API/TextEncoder)
  - [x] [TextDecoder](https://developer.mozilla.org/en-US/docs/Web/API/TextDecoder)
  - [x] [TextEncoderStream](https://developer.mozilla.org/en-US/docs/Web/API/TextEncoderStream)
  - [x] [TextDecoderStream](https://developer.mozilla.org/en-US/docs/Web/API/TextDecoderStream)
- [x] [Crypto API](https://developer.mozilla.org/en-US/docs/Web/API/Crypto)
  - [x] [randomUUID](https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID)
  - [x] [getRandomValues](https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues)
- [x] [SubtleCrypto](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto)
  - [x] [digest](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest)
  - [x] `CryptoKey`
  - [x] `generateKey()` for `HMAC`, `Ed25519`, `ECDSA`, `AES-CBC`, and `AES-CTR`
  - [x] `importKey('raw')` for `HMAC`, `PBKDF2`, `AES-CBC`, `AES-CTR`, and `Ed25519` public keys
  - [x] `exportKey('raw')` for extractable `HMAC`/`AES` keys, and generated `Ed25519`/`ECDSA` public keys
  - [x] `deriveBits()` for `PBKDF2` (`SHA-256/384/512`)
  - [x] `deriveKey()` for `PBKDF2` -> `HMAC`/`AES-CBC`/`AES-CTR`
  - [x] encrypt (`AES-CBC`, `AES-CTR` with `length = 128`)
  - [x] decrypt (`AES-CBC`, `AES-CTR` with `length = 128`)
  - [x] sign (`HMAC`, `Ed25519`, `ECDSA`)
  - [x] verify (`HMAC`, `Ed25519`, `ECDSA`)

Current `SubtleCrypto` scope:

| Area | Current support |
| --- | --- |
| `digest` | `SHA-1`, `SHA-256`, `SHA-384`, `SHA-512` |
| `HMAC` | `generateKey`, `importKey('raw')`, `exportKey('raw')`, `sign`, `verify` |
| `AES-CBC` | `generateKey`, `importKey('raw')`, `exportKey('raw')`, `encrypt`, `decrypt` |
| `AES-CTR` | `generateKey`, `importKey('raw')`, `exportKey('raw')`, `encrypt`, `decrypt` with `length = 128` only |
| `PBKDF2` | `importKey('raw')`, `deriveBits`, `deriveKey` with `SHA-256`, `SHA-384`, `SHA-512` |
| `Ed25519` | `generateKey`, `sign`, `verify`, `importKey('raw')` for public keys, `exportKey('raw')` for generated public keys |
| `ECDSA` | `generateKey`, `sign`, `verify`, `exportKey('raw')` for generated public keys |

Notes:

- `AES-GCM` is not implemented yet.
- `ECDSA` currently supports generated key pairs only; full `importKey()`/structured export formats are not implemented yet.
- `Ed25519` and `ECDSA` support in `exportKey('raw')` is intentionally limited to public keys.
- `PBKDF2` is a base-key flow only; use `importKey('raw', ...)` before `deriveBits()` or `deriveKey()`.

Minimal examples:

These snippets assume you are running with the browser-style host profile, so
`crypto.subtle` and `TextEncoder` are already available.

Runnable copies of these snippets live under `examples/crypto/` and can be run
with:

```bash
./vjsx --runtime browser --module ./examples/crypto/<file>.mjs
```

See also: `examples/crypto/README.md`

HMAC sign/verify:

File: `examples/crypto/hmac_sign_verify.mjs`

```js
const text = new TextEncoder().encode("hello");
const key = await crypto.subtle.importKey(
  "raw",
  new Uint8Array([1, 2, 3, 4]),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign", "verify"],
);

const sig = await crypto.subtle.sign("HMAC", key, text);
const ok = await crypto.subtle.verify("HMAC", key, sig, text);
console.log(sig.byteLength, ok);
```

AES-CBC encrypt/decrypt:

File: `examples/crypto/aes_cbc_encrypt_decrypt.mjs`

```js
const text = new TextEncoder().encode("hello");
const iv = new Uint8Array([15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
const key = await crypto.subtle.importKey(
  "raw",
  new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
  "AES-CBC",
  true,
  ["encrypt", "decrypt"],
);

const encrypted = await crypto.subtle.encrypt({ name: "AES-CBC", iv }, key, text);
const decrypted = await crypto.subtle.decrypt({ name: "AES-CBC", iv }, key, encrypted);
console.log(encrypted.byteLength, new TextDecoder().decode(decrypted));
```

PBKDF2 derive an AES key:

File: `examples/crypto/pbkdf2_derive_aes.mjs`

```js
const password = new TextEncoder().encode("password");
const baseKey = await crypto.subtle.importKey(
  "raw",
  password,
  "PBKDF2",
  false,
  ["deriveBits", "deriveKey"],
);

const aesKey = await crypto.subtle.deriveKey(
  {
    name: "PBKDF2",
    salt: new TextEncoder().encode("salt"),
    iterations: 1000,
    hash: "SHA-256",
  },
  baseKey,
  { name: "AES-CBC", length: 128 },
  true,
  ["encrypt", "decrypt"],
);

console.log(aesKey.algorithm.name, aesKey.algorithm.length);
```

Ed25519 and ECDSA:

File: `examples/crypto/signatures.mjs`

```js
const text = new TextEncoder().encode("hello");

const ed = await crypto.subtle.generateKey("Ed25519", false, ["sign", "verify"]);
const edSig = await crypto.subtle.sign("Ed25519", ed.privateKey, text);
console.log(await crypto.subtle.verify("Ed25519", ed.publicKey, edSig, text));

const ec = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  false,
  ["sign", "verify"],
);
const ecSig = await crypto.subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  ec.privateKey,
  text,
);
console.log(await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ec.publicKey,
  ecSig,
  text,
));
```
- [x] [Streams API](https://developer.mozilla.org/en-US/docs/Web/API/Streams_API)
- [x] [Event](https://developer.mozilla.org/en-US/docs/Web/API/Event/Event)
- [x] [FormData](https://developer.mozilla.org/en-US/docs/Web/API/FormData)
- [x] [Blob](https://developer.mozilla.org/en-US/docs/Web/API/Blob)
- [x] [File](https://developer.mozilla.org/en-US/docs/Web/API/File)
- [x] [Performance](https://developer.mozilla.org/en-US/docs/Web/API/Performance)
- [x] [Navigator](https://developer.mozilla.org/en-US/docs/Web/API/Navigator)
- [x] [Fetch API](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API)
  - [x] [Fetch](https://developer.mozilla.org/en-US/docs/Web/API/Fetch)
  - [x] [Headers](https://developer.mozilla.org/en-US/docs/Web/API/Headers)
  - [x] [Request](https://developer.mozilla.org/en-US/docs/Web/API/Request)
  - [x] [Response](https://developer.mozilla.org/en-US/docs/Web/API/Response)
- <i>More...</i>

### It's Fun Project. PRs Wellcome :)
