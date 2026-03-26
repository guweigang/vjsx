# VJSX

[V](https://vlang.io/) bindings to [QuickJS](https://bellard.org/quickjs/)
javascript engine. Run JS in V.

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
  rt := vjsx.new_runtime()
  ctx := rt.new_context()

  value := ctx.eval('1 + 2') or { panic(err) }
  ctx.end()

  assert value.is_number() == true
  assert value.is_string() == false
  assert value.to_int() == 3

  println(value)
  // 3

  // free
  value.free()
  ctx.free()
  rt.free()
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
  `fs`, `path`, and `process`
- `web.inject_browser_host(ctx, ...)`: browser-style host features under
  `web/`, including `window`, DOM bootstrap, and Web APIs

`web.inject_browser_host(...)` is now configurable, so you can expose only the
browser-facing modules you want, while still letting higher-level features like
`fetch` pull in their required Web API dependencies.

The legacy `ctx.install_host(...)` entrypoint still works as a compatibility
wrapper around `install_node_compat(...)`.

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
  rt := vjsx.new_runtime()
  ctx := rt.new_context()

  ctx.install_script_runtime(
    process_args: ['inline.js']
  )
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
  rt := vjsx.new_runtime()
  ctx := rt.new_context()

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
  - [ ] encrypt
  - [ ] decrypt
  - [ ] sign
  - [ ] verify
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
