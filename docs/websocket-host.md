# Native browser-style WebSocket host

Implemented in the independent worktree starting at `06faf1d`; no V standard
library changes, Node networking stack, business scheduler or Agent Loop.

## Contract

The node profile installs `WebSocket` by default. BrowserHostConfig also enables
it by default. Minimal profiles retain their smaller surface. Embedders can use
`session.try_install_websocket(WebSocketConfig{})` after configuring the host
policy, or `ctx.try_install_websocket_globals_policy(config, policy)` explicitly.
To customize limits before installation, use a bare session and install
NodeCompatConfig with `websocket: false`, then call the session method.

Supported: ws/wss (and http/https constructor aliases), subprotocol negotiation,
CONNECTING/OPEN/CLOSING/CLOSED, `url`, `protocol`, `extensions`, `bufferedAmount`,
`binaryType`, EventTarget listeners and onopen/onmessage/onerror/onclose.
Text, ArrayBuffer and ArrayBufferView sends preserve byte offsets. Binary
messages are Blob by default or ArrayBuffer when selected. `send(Blob)` is an
explicit TypeError. Close accepts 1000 or 3000–4999 and a UTF-8 reason up to
123 bytes. Duplicate close calls are idempotent. Cancellation during connection,
protocol failures and transport failures report error followed by abnormal close.
Listener exceptions end the connection and propagate through the existing lane
error path. No cookies, redirects, proxies, compression, HTTP/2, custom JS
headers, browser origin enforcement or Node `ws` API are claimed.

The implementation follows the browser API's relevant behavior, not full browser
network integration: <https://websockets.spec.whatwg.org/>. In particular it does
not implement Fetch/CSP/HSTS/cookie integration or WebIDL's full coercion rules.

## Ownership and bounds

A connection has one native worker, two notification socket pairs, a command
queue and an event queue. Only V-owned data crosses threads. The worker alone
owns TCP/TLS state. JS Values remain in the lane-owned record. Descriptor
notifications integrate with QuickJS's existing `qjs:os` read handlers; embedded
schedulers use the existing async-ready callback and `deliver_wakeup()`.
`needs_wakeup()` includes queued stream events. No timer poll loop is added.

Defaults: 32 active connections, 64 events/commands per queue, 1 MiB messages,
4 MiB queued bytes, 10 s connection/upgrade and I/O/close deadlines. An overflowing
receive queue reserves two terminal slots (error and close); it never silently
drops an accepted message. Outbound overflow throws QuotaExceededError and cancels
the connection. Connection IDs are monotonic decimal strings and never recycled;
late events cannot address a replacement connection. Release cancels, joins the
worker, closes every descriptor and frees the lane callback. Session shutdown
runs the same release path before destroying the JS Context.

TLS is OpenSSL native code with peer verification, default CA paths (or explicit
`ca_file`), SNI, DNS/IP identity verification, and no insecure override. TCP/TLS
and upgrade waits are cancellable and deadline-bound. The OS DNS resolver remains
synchronous: its elapsed time counts against the connection deadline, but a
blocked resolver cannot be interrupted by session cancellation. This is a known
remaining boundary, especially for shutdown latency on broken DNS. OpenSSL headers
and libraries are build dependencies; no Node or Python is needed by the shipped
native application. Linux/Windows code paths have not been executed in this run.

## Satori integration

`tests/integration/satori/package-lock.json` fixes adapter-lark 3.12.6, core 4.6.0,
Cordis/core 3.18.1, HTTP 0.6.3, protobufjs 8.8.1 and esbuild 0.27.4.
The build uses actual browser exports, a single ESM identity for Cordis services,
and the existing native `crypto` module. No empty builtin substitutes are used.
`compat.mjs` sets the HTTP-created socket's binaryType and subclasses the real
LarkBot only to declare the Satori service dependency and fence/clear its upstream
global token timer on disposal. The native navigator exposes only a truthful
`vjsx/<version>` userAgent for browser dependency feature selection.

The local fixture implements HTTP gateway discovery, token/bot metadata and
Feishu's protobuf Frame schema. It receives application ping and sends pong plus
a menu-command event; the real adapter dispatches it and returns its protobuf ack.
This is a local protocol fixture, not a real Feishu account or service test.
The fixture secret/token are constants. No other project secrets are read.

## Reproducing validation

Build against this checkout rather than a global `~/.vmodules/vjsx` symlink:

```sh
export VJS_QUICKJS_PATH=/path/to/compatible/quickjs
v -path "$PWD/..|@vlib|@vmodules" -cc clang -d build_quickjs -o /tmp/vjsx-ws ./cli_runner_bin
v -path "$PWD/..|@vlib|@vmodules" -cc clang -d build_quickjs -o /tmp/ws-lifecycle tests/websocket_lifecycle_probe.v
v -path "$PWD/..|@vlib|@vmodules" -cc clang -d build_quickjs -o /tmp/ws-timeout tests/websocket_timeout_probe.v
python3 tests/websocket_network.py /tmp/vjsx-ws /tmp/ws-lifecycle /tmp/ws-timeout
npm ci --ignore-scripts --prefix tests/integration/satori
node tests/integration/satori/build.cjs
python3 tests/integration/satori/fixture.py
# In another terminal:
/tmp/vjsx-ws compile --bundle tests/integration/satori/probe.bundle.mjs -o /tmp/satori.vjsx
/tmp/vjsx-ws run /tmp/satori.vjsx
/tmp/vjsx-ws build tests/integration/satori/probe.bundle.mjs -o /tmp/satori-native
/tmp/satori-native
```

Python/Node/OpenSSL CLI above are development fixtures/build tools. The resulting
native app contains its runtime and bundle. Genuine Feishu credentials and a
customer installation are still needed for external end-to-end acceptance.

Recorded machine: macOS arm64, V 0.5.2 e21021d. A new local-dev validation
confirmed `/Users/guweigang/local/v` on branch `local-dev` at full revision
`e21021d10433ad9fa7fd45fd63e2dee79ec612ef`, matching the executable. Debug builds
use the installed OpenSSL 4.0.3; the production build script statically links
OpenSSL 3.5.9 and has only system dynamic dependencies. The checkout's
`.v-version` is older and was intentionally left unchanged. Existing session test
Option expressions were parenthesized and given explicit panic messages to
compile on this compiler; their assertions are unchanged.

Machine-readable test output is saved in `websocket-validation-results.json`.
The self-cleaning Satori runner is `python3 tests/integration/satori/run.py /tmp/vjsx-ws`.

## local-dev compatibility follow-up

The local-dev rebuild found two issues in this worktree:

- `js_int()` used QuickJS's 32-bit constructor even when V `int` is 64-bit.
  It now uses `JS_NewInt64` to create a JavaScript Number. The new regression
  checks direct construction and object field conversion at signed 32-bit,
  2^32 and JavaScript exact-integer boundaries. `js_big_int` remains available
  for exact i64 values; JavaScript Number precision rules still apply.
- `web.delete_bootstrap()` accidentally contained installation code referring
  to `normalized`, which exists only in `inject_browser_host()`. That misplaced
  block was removed. A browser-profile regression exercises bootstrap cleanup
  and verifies that it preserves the WebSocket constructor's identity.

Validation builds the CLI and production executable with local-dev, runs every
source `_test.v` file, and reruns the real network and Satori fixtures against
that production binary. All build artifacts, compiler/tool caches and logs are
under `.build/local-dev/`; V and the primary repository are read-only inputs.
The native CLI is retained as `.build/local-dev/vjsx-release-final` for review.
The new run's results are in `local-dev-validation-results.json`.

Completed local-dev follow-up: all 42 source test files passed (the V runner also
executed two formatter-generated copies, giving 44/44 entries). The production
binary passed all 27 real WS/WSS cases, including 128 same-session connections
for each transport, TLS rejection and cancellation/cleanup checks. Node, packaged
`.vjsx` and native Satori execution each received the event and returned the
protobuf ack. The V checkout and executable hash were unchanged. Other changes
appeared in the primary checkout during the run; they were left untouched and
were not used as this run's module source. External MySQL is gated by test
configuration and was not contacted.
