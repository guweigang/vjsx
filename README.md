# VJS

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
- Top-Level `await` support. using `vjs.type_module`.

## Install

```bash
v install herudi.vjs
```

## Build With Local QuickJS Source

If you already have a local QuickJS checkout, you can compile `vjs` against the
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
- In this mode `vjs` compiles QuickJS C sources directly.
- Without `-d build_quickjs`, `vjs` keeps using the bundled prebuilt
  libraries from `libs/`.

## Basic Usage

Create file `main.v` and copy-paste this code.

```v
import herudi.vjs

fn main() {
  rt := vjs.new_runtime()
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

Explore [examples](https://github.com/herudi/vjs/tree/master/examples)

If you want the smallest file-based example, see
`examples/run_file.v` together with `examples/js/foo.js`.

## CLI

You can also run JS files directly from the repository:

```bash
./vjs ./tests/test.js
```

Module mode:

```bash
./vjs --module ./examples/js/main.js
```

TypeScript entry files are also supported:

```bash
./vjs ./tests/ts_basic.ts
./vjs --module ./tests/ts_module_runtime.mts
```

TypeScript module graphs are also supported, including:

- relative `.ts` / `.mts` imports
- nearest `tsconfig.json`, including `extends`
- `compilerOptions.baseUrl` and `paths`
- bare package imports resolved from local `node_modules`
- package `exports` root and explicit subpath entries

Options:

- `--module`, `-m`: run the file as an ES module

Currently this TypeScript support is runtime transpilation for the entry file.
It is a good fit for standalone `.ts` scripts and `.mts` modules. Project-wide
features like full `tsc` diagnostics, `references`, and broader Node
compatibility are still out of scope for now.

The wrapper script will use `VJS_QUICKJS_PATH` when it is set. If it is not
set, it will try `../quickjs` relative to the repository root.

> Currently support linux/mac/win (x64).

> in windows, requires `-cc gcc`.

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

ctx.eval(code, vjs.type_module) or { panic(err) }
ctx.end()
```

## Web Platform APIs

Inject Web API to vjs.

```v
import herudi.vjs
import herudi.vjs.web

fn main() {
  rt := vjs.new_runtime()
  ctx := rt.new_context()

  // inject all
  web.inject(ctx)

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
