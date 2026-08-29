# VJSX

<p align="center">
  <img src="assets/vjsx_brand.jpg" alt="VJSX brand" width="720" />
</p>

[V](https://vlang.io/) bindings to [quickjs-ng](https://quickjs-ng.github.io/quickjs/)
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
- Managed runtime turns with memory, stack, GC and execution-time limits.
- Thread-safe `runtimejs.SessionLane` serialization with bounded admission.
- QuickJS memory snapshots, lifecycle state and bounded turn observations.

Hosting documentation:

- [Embedding VJSX](docs/EMBEDDING.md) for the host-first extension path.
- [Managed Runtime Hosting](docs/MANAGED_RUNTIME_HOSTING.md) for production
  limits, lifecycle, lanes, observations, capability hardening, and migration.
- [Runtime Contract](docs/RUNTIME_CONTRACT.md) for ownership and engine/host
  boundaries.

## Install

```bash
v install vjsx
```

## Build With Local quickjs-ng Source

`vjsx` can compile against a managed local QuickJS source checkout directly
instead of the bundled prebuilt archives. The managed checkout is currently
quickjs-ng, but hosts do not need to know that implementation detail.

This is useful when:

- you are on an unsupported architecture such as `macOS arm64`
- you want to use a newer quickjs-ng version
- you do not want to maintain extra prebuilt `.a` files inside this repo

Example:

```bash
VJS_QUICKJS_PATH=$(./scripts/ensure-quickjs.sh) \
v -d build_quickjs run main.v
```

Notes:

- `vjsx` wrapper scripts download a managed checkout to `.deps/quickjs` under
  the calling repository when no compatible local checkout is found.
- Direct `v` invocations should use `scripts/ensure-quickjs.sh` to prepare and
  print the managed checkout path before compilation starts.
- The managed quickjs-ng checkout defaults to `v0.15.1`; set `QUICKJS_REF` to
  build against a different tag or branch.
- Set `VJS_QUICKJS_WORK_ROOT` to choose where `.deps/quickjs` is created, or
  `QUICKJS_DIR` to choose the exact checkout path.
- `VJS_QUICKJS_PATH` can still point to an explicit source root that contains
  `quickjs.c`, `quickjs-libc.c`, `quickjs.h`, and `quickjs-libc.h`.
- In this mode `vjsx` compiles QuickJS C sources directly.
- Legacy Bellard QuickJS source builds are still available with
  `-d quickjs_legacy`.
- `-d build_quickjs` is required for new builds. vjsx no longer ships bundled
  QuickJS archives because the managed source checkout is the compatibility
  boundary.

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

## Embedded Host Quick Start

If you are embedding `vjsx` into another V project, start from
`runtimejs.ExtensionSession` rather than lower-level runtime plumbing.

```v
import runtimejs
import vjsx

fn host_api() vjsx.HostValueBuilder {
	return vjsx.host_object(vjsx.HostObjectField{
		name:  'app'
		value: vjsx.host_object(vjsx.HostObjectField{
			name:  'name'
			value: vjsx.host_value('demo-host')
		})
	})
}

fn main() {
	mut extension_session := runtimejs.new_node_extension_session(
		vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
			process_args: ['extension.mjs']
		},
		vjsx.HostApiConfig{},
		host_api(),
	)
	defer {
		extension_session.close()
	}

	mut extension := extension_session.load_extension('./examples/js/host_extension.mjs',
		vjsx.ScriptPluginHooks{}) or { panic(err) }
	defer {
		extension.close()
	}

	result := extension.call_export('greet', 'world') or { panic(err) }
	defer {
		result.free()
	}
	println(result.to_string())
}
```

For the full host-first embedding guidance, see
[`docs/EMBEDDING.md`](docs/EMBEDDING.md).

Long-lived hosts should run user work through `RuntimeSession.run_turn(...)` or
transfer the session to `runtimejs.SessionLane`. See the
[runtime contract](docs/RUNTIME_CONTRACT.md#turn-and-lifecycle-contract) for
the lifecycle contract, and [Managed Runtime Hosting](docs/MANAGED_RUNTIME_HOSTING.md)
for limits, serialized lanes, observations, capability hardening, and migration.

## Run

```bash
v run main.v
```

With the managed local QuickJS source checkout:

```bash
VJS_QUICKJS_PATH=$(./scripts/ensure-quickjs.sh) \
v -d build_quickjs run main.v
```

Explore [examples](https://github.com/guweigang/vjsx/tree/master/examples)

If you want the smallest file-based example, see
`examples/run_file.v` together with `examples/js/foo.js`.

If you want the recommended embedded-host flow, see
`examples/embedding_extension.v` together with
`examples/js/host_extension.mjs`.

If you also want an example that shows host modules plus manifest-defined hook
names, see `examples/embedding_extension_manifest.v` together with
`examples/js/host_extension_manifest.mjs`.

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

Runtime compatibility checks are available for hosts that need to verify the
portable runtime before installing or loading packages:

```bash
./vjsx --help
./vjsx --version
./vjsx check-runtime --runtime node
./vjsx capabilities
./vjsx capabilities --runtime browser
./vjsx check --module ./tests/ts_module_runtime.mts
```

`vjsx capabilities` prints the host features exposed by the built runtime
profiles, including globals, browser-style APIs, and Node-style modules. Use
`--runtime node`, `--runtime script`, or `--runtime browser` to inspect one
profile.

Self-contained UMD/CommonJS files can be compiled to QuickJS bytecode during a
build:

```bash
./vjsx compile --entry-only --runtime node ./vendor/parser.umd.js -o parser.qbc
```

The artifact contains a compiled CommonJS factory and preserves
`module.exports`. It can be embedded and loaded without the original source or
a module resolver:

```v
bytecode := os.read_bytes('parser.qbc')!
mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{},
	vjsx.NodeRuntimeConfig{})
ctx := session.context()
mut parser_module := ctx.load_bytecode(bytecode)!
parser_class := parser_module.get('Parser')!
```

Retain the returned `ScriptModule` (and any constructed JS objects) to reuse
the initialized module in a long-lived context. Bytecode artifacts are checked
for vjsx format/runtime, QuickJS ABI, checksum, and runtime profile before
deserialization. QuickJS bytecode is not safe for hostile input, so only load
artifacts produced by a trusted build. `--entry-only` does not bundle imports;
it is intended for self-contained files.

For a project with static imports, TypeScript, JSON, or local CommonJS
dependencies, compile the reachable module graph into one application bundle:

```bash
./vjsx compile --bundle --runtime node ./src/main.ts -o myapp.vjsx
./vjsx run myapp.vjsx
```

The output name convention is `<appname>.vjsx`. It is a self-contained,
versioned vjsx application artifact rather than a native machine executable.
The bundle stores the entry manifest and each transformed module as QuickJS
bytecode. At runtime, imports are linked from the in-memory bundle, so project
sources and `node_modules` are not read, parsed, or compiled again.

Embedders can load the same artifact and retain its initialized namespace:

```v
bundle := os.read_bytes('myapp.vjsx')!
mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{},
	vjsx.NodeRuntimeConfig{})
ctx := session.context()
mut app := ctx.load_bundle(bundle)!
result := app.call_export('main')!
```

Keep the returned `ScriptModule` alive to preserve module-level objects and
state across calls. `.vjsx` loading validates the container format, checksum,
vjsx version, QuickJS ABI, and runtime profile before evaluating its entry.
Only statically reachable dependencies are included; dynamic dependency names
that cannot be determined during the build are not supported by this first
bundle format. As with `.qbc`, load only trusted artifacts.

To package that bundle as a native single-file application:

```bash
./vjsx build --runtime node ./src/main.ts -o myapp
./myapp arg1 arg2
```

`vjsx build` uses the platform-specific `vjsx-app-runner` installed next to
the `vjsx` CLI. It appends the generated `.vjsx` bundle and a fixed 64-byte
footer to a copy of that runner. The footer records its format version, bundle
length, and SHA-256 checksum, allowing the runner to locate and validate the
bundle without reading the native executable body. Use `--runner <path>` or
`VJS_APP_RUNNER` to select an explicit runner.

The resulting file is a native V/QuickJS executable containing QuickJS
bytecode; it is not JavaScript AOT-compiled to machine code. It does not expose
the package-management or compilation commands of the regular `vjsx` CLI.

To measure parser startup and steady-state calls separately:

```bash
VJS_QUICKJS_PATH=$(./scripts/ensure-quickjs.sh) \
  v -d build_quickjs run ./examples/bytecode_parser_benchmark.v parser.qbc
```

Packages can be installed without a local Node/npm dependency:

```bash
./vjsx install is-number@7.0.0
./vjsx install
./vjsx install --dev typescript
./vjsx repair
./vjsx repair defuddle
./vjsx ls
./vjsx ls --json
./vjsx ls --depth 0
./vjsx ls --omit=dev
./vjsx ls --omit=dev,optional
./vjsx remove is-number
./vjsx uninstall typescript
```

When package specs are provided, `vjsx install` updates `package.json` in the
same way users expect from a package installer: regular installs are written to
`dependencies`, and `--dev` installs are written to `devDependencies`. When no
package spec is provided, the installer reads `dependencies` from
`package.json`; pass `--dev` to include `devDependencies`.

`vjsx remove` and `vjsx uninstall` remove packages from `package.json`,
`package-lock.json`, and `node_modules`. After removing a top-level dependency,
vjsx recomputes package reachability and removes transitive packages that are no
longer required while preserving dependencies shared by the remaining roots.

`vjsx repair` restores packages at the exact versions recorded in
`package-lock.json`. With no package names it repairs all root dependencies;
with package names it repairs those packages and their locked dependencies. It
does not upgrade versions or change dependency declarations.

`vjsx ls` and `vjsx list` print an npm-style dependency tree from the current
`package-lock.json` and `node_modules`. Pass `--json` for npm-style structured
output, `--depth 0` to show only top-level dependencies, `--omit=dev`,
`--omit=optional`, or `--omit=peer` to hide selected dependency classes, or pass
package names to inspect selected roots. JSON output includes
`dependencyType`, with values `dev`, `optional`, `peer`, or `prod` when the
dependency is not in one of the other root dependency sections.

`vjsx install` writes npm-compatible `package-lock.json` v3 data and reuses an
existing lockfile when present. It also supports basic `workspaces` entries by
linking local packages into `node_modules`, and reports `peerDependencies` as
warnings without blocking installation.

Before changing the project's `node_modules`, `vjsx install` and `vjsx repair`
stage requested packages in a temporary package tree and compile each directly
requested package's default entry plus its statically reachable module graph
against the vjsx Node-style host. Package code is not evaluated during this
check. A reachable unsupported host module or native addon rejects the
operation; unused `.node` files, `binding.gyp`, unselected exports, lifecycle
scripts, and compatibility that cannot be determined statically do not block
installation. Packages without an importable default entry and packages with
install lifecycle scripts produce warnings. Running `vjsx check` on the real
application entry remains the final compatibility check for subpath and dynamic
imports selected by the application.

The installer targets package compatibility, not full npm CLI compatibility.
It does not run lifecycle scripts such as `postinstall`, and it does not require
Node/npm to be installed locally.

To build a standalone `vjsx` binary:

```bash
./scripts/build-vjsx.sh
```

The build writes `bin/vjsx` and `bin/vjsx-app-runner` by default. Set
`VJS_OUT=/path/to/vjsx` and `VJS_APP_RUNNER_OUT=/path/to/vjsx-app-runner` to
choose other output paths.

On Windows, use the PowerShell build script:

```powershell
.\scripts\build-vjsx.ps1
```

The Windows build defaults to MSVC (`-cc msvc`), matching the preferred VTable
sidecar release strategy. In that mode the script builds quickjs-ng with
CMake/Ninja, links the generated `qjs.lib` through `-d link_quickjs`, and sets
`VJS_QUICKJS_LIB_PATH` for the V build. Override with `-Compiler`, `VJS_V_CC`,
or an explicit `-cc` in `VJS_V_FLAGS` only when you intentionally want another
C toolchain.

Release binaries are built by the `Release Binaries` GitHub workflow. It
produces platform-specific archives:

- `vjsx-darwin-arm64.tar.gz`
- `vjsx-darwin-x64.tar.gz`
- `vjsx-linux-arm64.tar.gz`
- `vjsx-linux-x64.tar.gz`
- `vjsx-windows-x64.zip`

The workflow can be run manually from GitHub Actions. Pushing a tag like
`v0.1.0` also creates a GitHub Release and uploads those archives. Downstream
projects such as VTable should download the archive matching their target OS
and CPU, then place `vjsx`/`vjsx.exe` and `vjsx-app-runner`/
`vjsx-app-runner.exe` in their packaged runtime directory. The runner is only
needed when producing native single-file applications.

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

Runtime support files are embedded into release binaries. Internally, embedded
Web/Node compatibility modules and TypeScript support files are loaded through
stable virtual module names using the `vjsx://` scheme, such as
`vjsx://web/js/fetch.js` or
`vjsx://thirdparty/typescript/lib/vjs_ts_bootstrap.js`. Hosts should treat
those modules as `vjsx` implementation details and use the public runtime APIs
instead of depending on repository-relative asset paths. `VJSX_ASSET_ROOT` and
`ContextConfig.asset_root` remain development override hooks; production
binaries fall back to embedded assets. The full JS/TS runtime asset loading
contract is documented in [`docs/RUNTIME_CONTRACT.md`](docs/RUNTIME_CONTRACT.md).

When embedding `vjsx` in a long-lived process, always pair each created
`Runtime`/`Context` with an explicit `free()`. Repeated TypeScript bootstrap
work in the same process assumes those runtimes are torn down deliberately;
leaking them can surface later as hard-to-diagnose bootstrap failures.

If you want one owner object for embedded use, prefer `vjsx.new_runtime_session()`
and `session.close()`, which tear down the `Context` and `Runtime` together.

Managed sessions can also interrupt non-yielding JavaScript with a CPU deadline
or a thread-safe cancellation request:

```v
session.set_deadline(time.now().add(2 * time.second))
// May be called from another thread while QuickJS is executing.
session.cancel()
session.clear_deadline()
```

QuickJS checks these controls from its interrupt handler while executing JS.
An interrupted session returns `RuntimeInterruptedError`, reports its reason via
`session.interrupt_reason()`, and must be closed rather than reused.
For Node-style hosts, that teardown also closes tracked `sqlite` / `mysql`
connections that were left open by JS code.

If you also want TypeScript/module-aware file loading from the same session,
use `runtimejs.new_script_runtime_session(...)` or
`runtimejs.new_node_runtime_session(...)`. Those session helpers install the
runtime bridge so embedders can call higher-level methods like:

- `session.run(path)`
- `session.run_script(path)`
- `session.run_module(path)`
- `session.load_module(path)`
- `session.import_module(path)`
- `session.import_module_with_host(path, host_api)`
- `session.load_plugin(path, hooks)`
- `session.load_plugin_with_host(path, hooks, host_api)`
- `session.call_module_export(path, export_name, ...)`
- `session.call_module_export_with_host(path, export_name, host_api, ...)`
- `session.call_module_method(path, export_name, method_name, ...)`
- `session.call_module_method_with_host(path, export_name, method_name, host_api, ...)`
- `session.call_default_export_method(path, method_name, ...)`
- `session.call_default_export_method_with_host(path, method_name, host_api, ...)`

For embedded host use, the recommended abstraction ladder is now:

- `vjsx.RuntimeSession`: core lifecycle and loading
- `runtimejs.ExtensionSession`: default embedder-facing session
- `runtimejs.ExtensionHandle`: one loaded extension instance with lifecycle
  hooks plus regular export calls

That path is documented in [`docs/EMBEDDING.md`](docs/EMBEDDING.md), together
with:

- the recommended stopping point to avoid over-design
- API surface guidance for default vs advanced helpers
- stability notes for likely long-term vs de-emphasized APIs
- a convergence checklist for future cleanup without more abstraction growth
- host API shape guidance
- `load_extension(...)` usage
- optional JS/TS manifest support
- optional manifest `services` support

`vjsx.new_runtime()` and `rt.new_context()` are still available for advanced
manual ownership cases, but then the caller is responsible for pairing them
with `ctx.free()` and `rt.free()` correctly.

The wrapper script will use `VJS_QUICKJS_PATH` when it is set. If it is not
set, it will download or reuse a managed checkout under the calling
repository's `.deps/quickjs`, matching the CI build path.

> Currently support linux/mac/win (x64).

> On Windows, release builds prefer MSVC (`-cc msvc`).

## Host Profiles

The runtime is now split into clearer layers:

- `ctx.install_runtime_globals(...)`: reusable globals like `Buffer`, timers,
  `URL`, and `URLPattern`
- `ctx.install_node_compat(...)`: Node-like host features such as `console`,
  `fs`, `path`, `os`, `child_process`, `process`, standard `fetch` globals,
  `sqlite`, and optional `mysql`
- `web.inject_browser_host(ctx, ...)`: browser-style host features under
  `web/`, including `window`, DOM bootstrap, and Web APIs

`web.inject_browser_host(...)` is now configurable, so you can expose only the
browser-facing modules you want, while still letting higher-level features like
`fetch` pull in their required Web API dependencies.

The legacy `ctx.install_host(...)` entrypoint still works as a compatibility
wrapper around `install_node_compat(...)`.

The Node profile accepts both legacy bare and modern `node:` builtin names for
the implemented filesystem modules:

```js
import fs from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
// `fs`, `fs/promises`, and `node:fs/promises` are also available.
```

The promise filesystem modules expose the existing asynchronous `readFile`,
`writeFile`, `exists`, `mkdir`, `readdir`, `rm`, `stat`, `copyFile`, `rename`,
`readJson`, and `writeJson` helpers. They are a practical subset rather than a
complete implementation of Node's `FileHandle` API.

`crypto` and `node:crypto` provide an Ed25519-focused compatibility subset:

- `createPrivateKey()` with unencrypted PKCS8 PEM/DER keys
- `createPublicKey()` with SPKI PEM/DER keys or an Ed25519 private `KeyObject`
- `sign(null, data, privateKey)` and `verify(null, data, publicKey, signature)`
- `generateKeyPairSync("ed25519")` and callback-based `generateKeyPair()`
- `KeyObject.export()` to PKCS8/SPKI PEM or DER

Encrypted private keys and non-Ed25519 algorithms are intentionally rejected.
See [`docs/NODE_COMPATIBILITY.md`](docs/NODE_COMPATIBILITY.md) for the complete
specifier matrix, examples, compatibility differences, key formats, and
security boundaries.

For the embedding ownership, event-loop, timer, diagnostics, limits, and profile
contracts, see [`docs/RUNTIME_CONTRACT.md`](docs/RUNTIME_CONTRACT.md).
That contract also records the QuickJS FFI ownership rules: borrowed V string
pointers must not be freed manually, QuickJS-owned strings use
`JS_FreeCString(...)`, and `JSValue` ownership must stay explicit across wrapper
boundaries.

For embedders, `ctx.install_host_api(...)` provides a more explicit way to
expose host globals and modules to JS/TS extension code without hand-rolling
`js_module(...).create()` at every call site.

Useful embedders helpers include:

- `vjsx.host_value(...)`
- `vjsx.host_object(...)`
- `vjsx.host_module_exports(...)`
- `vjsx.host_module_object(...)`

Database host modules:

- `import { open } from "sqlite"` is available in the default Node-style host
  profile
- `import { connect } from "mysql"` is also exposed, but the real V MySQL
  backend is only compiled when you pass `-d vjsx_mysql`
- The CLI uses `-cc clang` by default and forwards extra V compiler flags
  through `VJS_V_FLAGS`, for example:
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

`ScriptRuntimeConfig` keeps `path`, `os`, and `process` enabled by default for
backwards compatibility, but embedders running untrusted code can disable each
capability explicitly. Direct `sqlite` and `mysql` modules are disabled by
default in the script profile and must be opted into; the full Node profile
continues to install them.

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
    process: false
    path: false
    os: false
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

## Install Host API

```v
import vjsx

mut session := vjsx.new_runtime_session()
defer {
  session.close()
}
ctx := session.context()

ctx.install_host_api(
  globals: [
    vjsx.HostGlobalBinding{
      name:  'appName'
      value: vjsx.host_value('demo')
    },
  ]
  modules: [
    vjsx.HostModuleBinding{
      name: 'host-tools'
      install: vjsx.host_module_exports(
        vjsx.HostModuleExport{
          name:  'answer'
          value: vjsx.host_value(42)
        },
        vjsx.HostModuleExport{
          name: 'describe'
          value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
            return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
              return ctx.js_string('host:' + args[0].str())
            })
          }
        },
      )
    },
  ]
)

ctx.eval('
  import hostTools, { answer, describe } from "host-tools";
  globalThis.result = [
    appName,
    String(answer),
    describe("ok"),
    String(hostTools.answer)
  ].join("|");
', vjsx.type_module) or { panic(err) }
```

## Install Host Object

```v
ctx.install_host_api(
  globals: [
    vjsx.HostGlobalBinding{
      name: 'host'
      value: vjsx.host_object(
        vjsx.HostObjectField{
          name:  'name'
          value: vjsx.host_value('demo')
        },
        vjsx.HostObjectField{
          name: 'math'
          value: vjsx.host_object(
            vjsx.HostObjectField{
              name: 'add'
              value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
                return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
                  return ctx.js_int(args[0].to_int() + args[1].to_int())
                })
              }
            },
          )
        },
      )
    },
  ]
  modules: [
    vjsx.HostModuleBinding{
      name: 'host-service'
      install: vjsx.host_module_object(
        vjsx.HostObjectField{
          name:  'version'
          value: vjsx.host_value('v1')
        },
        vjsx.HostObjectField{
          name: 'greet'
          value: fn [ctx] (ctx2 &vjsx.Context) vjsx.Value {
            return ctx.js_function(fn [ctx] (args []vjsx.Value) vjsx.Value {
              return ctx.js_string('hello:' + args[0].str())
            })
          }
        },
      )
    },
  ]
)
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

Runnable copies of these snippets live under `examples/webcrypto/` and can be run
with:

```bash
./vjsx --runtime browser --module ./examples/webcrypto/<file>.mjs
```

See also: `examples/webcrypto/README.md`

HMAC sign/verify:

File: `examples/webcrypto/hmac_sign_verify.mjs`

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

File: `examples/webcrypto/aes_cbc_encrypt_decrypt.mjs`

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

File: `examples/webcrypto/pbkdf2_derive_aes.mjs`

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

File: `examples/webcrypto/signatures.mjs`

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
