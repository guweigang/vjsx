# vjsx Runtime Contract

This document records the current embedding contract for `vjsx` as a stable JS
runtime platform. It focuses on ownership boundaries: what QuickJS owns, what
`RuntimeSession` owns, and what the host must still provide.

## Ownership Boundary

QuickJS owns engine internals:

- JS heap and garbage collection
- stack limits and memory limits
- Promise jobs and microtasks
- the underlying `qjs:os` timer queue when compatibility timer mode is selected
- pending job execution through `JS_ExecutePendingJob`

`vjsx` owns session-level platform state:

- `RuntimeSession` lifecycle and idempotent close
- event-loop facade state
- runtime-owned timer records, or QuickJS timer wakeup hints in compatibility mode
- Promise capabilities and queued plain-data completions for host async operations
- diagnostic records and diagnostic handlers
- profile metadata and installed module registry
- optional limits for `vjsx` facade state

The host owns platform scheduling and I/O:

- choosing where a session runs
- delivering scheduled wakeups
- calling `pump_once()`, `drain_ready_tasks()`, or `pump_until_idle()` on the
  session-owning lane/thread
- implementing host I/O such as HTTP, DB, filesystem, sockets, and queues

The important rule is: **do not reimplement the QuickJS Promise job queue**.
Runtime-owned timers are an optional host-driven clock boundary; their callbacks
still run on the session lane and any resulting Promise work remains in QuickJS.

## QuickJS FFI Ownership Contract

The V/QuickJS boundary must treat ownership explicitly. Most pointers exposed
by V strings and QuickJS values are borrowed, not heap blocks owned by `vjsx`.

Rules for string pointers:

- `some_v_string.str` is a borrowed pointer into V-managed storage. Do not call
  `free(...)` on it.
- If a C API needs a stable or mutable buffer beyond the immediate call, copy
  the bytes on the C side and free that C-owned copy there.
- Only free memory that was allocated by the matching allocator and whose
  ownership was explicitly transferred to the caller.
- QuickJS strings returned by `JS_ToCString(...)` must be released with
  `JS_FreeCString(...)`, not with V `free(...)`.

Rules for QuickJS values:

- A returned `JSValue` is owned by the caller and must eventually be released
  with `JS_FreeValue(...)`, normally through `Value.free()`.
- A `JSValueConst` is borrowed. Do not free it unless it has first been
  duplicated with `JS_DupValue(...)` or otherwise documented as caller-owned.
- When a QuickJS API consumes a value, such as `JS_SetProperty*`, do not free
  the consumed value again unless the API contract says it was not consumed.
- Keep value ownership visible at wrapper boundaries. Prefer returning
  `vjsx.Value` only when the wrapper clearly owns the underlying `JSValue`.

Windows and MSVC are the strictest proving ground for this contract. The
quickjs-ng `JSValue` representation is ABI-sensitive on 64-bit platforms, and
MSVC heap checks catch borrowed-pointer frees that may appear to work on macOS.
For new FFI calls that return or transport `JSValue`, prefer a tiny C wrapper
with an out parameter when there is any ABI doubt, and cover it with a Windows
smoke test.

Do not paper over FFI crashes by permanently skipping host capabilities on one
platform. Temporary platform guards are acceptable while isolating a native
crash, but the final fix must either restore the capability or document a real
unsupported platform boundary.

## Event Loop Contract

`RuntimeSession.configure_event_loop(...)` defines the host/runtime boundary:

- `session_id` identifies the runtime to the host.
- `now_fn` provides the time source.
- `wake_fn` asks the host to schedule a future wakeup.
- `cancel_wake_fn` cancels a pending host wakeup.
- `async_ready_fn` tells the host that a worker completion is queued and the
  session-owning lane should call `deliver_wakeup(0)`.
- `runtime_owned_timers` selects the session timer state machine. When false,
  the existing `qjs:os.setTimeout` compatibility path remains active.

`configure_event_loop(...)` also installs the timer wakeup bridge used by the
JS timer wrapper. Hosts should not call `install_timer_wakeup_bridge()` directly.

Wakeup requests include a monotonically increasing `generation`. Hosts should
store both `wake_at_ms` and `generation` and ignore stale wakeups whose pair no
longer matches the latest pending request.

For lane-owned runtimes, the caller thread should not touch the lane-owned
`RuntimeSession` directly. Use `SessionLane.deliver_wakeup(...)`; stale scheduled
wakeups are ignored by generation.

## Host Async Operation Contract

`start_host_async_operation(...)` creates a caller-owned JS Promise and keeps
its resolve/reject functions inside the session. Give background code only the
returned `completion` port and `cancel` token. Neither type contains a
`JSContext` or `Value`.

The worker may submit text/bytes success, rejection, or cancellation. Submission
only appends plain V-owned data to a locked queue and invokes `async_ready_fn`.
The owning session/lane later calls `drain_host_async_events()` or
`deliver_wakeup(...)`; only that path constructs JS values, invokes the Promise
capability, frees resolve/reject, and drains Promise jobs.

Completion, explicit cancellation, timeout, and close share a first-terminal
event gate. Losing completions return `false`. Timeout and close mark the worker
token cancelled. Close rejects still-pending capabilities with
`SessionClosedError` before destroying the context, but shutdown does not run
new user Promise continuations.

`RuntimeHostAsyncOperation.bind_abort_signal(...)` attaches an AbortSignal on
the owning lane and removes the listener when the Promise settles. The embedded
`__vjsxCancel` property is an implementation hook, not a general JS API.

For host-to-runtime streaming, `RuntimeHostStreamMailbox` is the minimum bounded
protocol: `try_push()` accepts a copied frame only while capacity is available,
and returns `false` to signal backpressure. The lane acknowledges capacity by
calling `drain()`. Producers must retry or pause after `false`; frames are never
silently dropped and the mailbox never grows past its configured capacity.

## Timer Contract

Global callback timers keep standard callback semantics:

```js
setTimeout(callback, delay, ...args)
```

`vjsx` does not treat callback timer arguments as options. In particular,
`setTimeout(cb, delay, { signal })` is not a supported cancellation API because
the third argument belongs to `...args`.

Node-compatible promise timers are exposed through:

```js
import { setTimeout } from "node:timers/promises";

await setTimeout(1000, "value", { signal });
```

`node:timers/promises` supports `AbortSignal` and remains implemented on top of
global `setTimeout` / `clearTimeout`. In runtime-owned mode those globals create
session timer records; otherwise QuickJS owns the real timer queue.

In compatibility mode, timer wakeup hints are not timers. They only let the host
schedule an efficient lane/session wakeup instead of polling. In runtime-owned
mode, `deliver_wakeup(generation)` fires due one-shot/interval callbacks on the
owner lane and reschedules the earliest remaining deadline.

## Node Builtin Module Contract

The full `node` profile installs the filesystem aliases `fs`, `node:fs`,
`fs/promises`, and `node:fs/promises`, plus the Ed25519-focused `crypto` and
`node:crypto` modules. The `script` and `node_compat_minimal()` profiles do not
install the filesystem or crypto modules.

These modules are compatibility subsets. Their supported exports, behavioral
differences from Node.js, key formats, and security boundaries are documented
in [`NODE_COMPATIBILITY.md`](NODE_COMPATIBILITY.md). New exports should be added
to that document and covered by the executable compatibility test before they
are treated as part of the runtime contract.

## Diagnostics Contract

`RuntimeSession` records runtime diagnostics at facade boundaries such as:

- `pump_once()` QuickJS job execution failures
- `resolve_value()` rejected Promise resolution
- `call()` failures
- `call_global()` missing global functions
- `vjsx` facade limit violations

Diagnostics are retained in a bounded ring buffer. The default maximum is
`default_runtime_session_max_diagnostics`.

Hosts may subscribe with:

```v
session.set_diagnostic_handler(fn (diagnostic vjsx.RuntimeSessionDiagnostic) {
    // log, metric, event, or host-specific error reporting
})
```

The handler is called synchronously after the diagnostic is recorded. It does
not swallow the original error; facade APIs continue returning errors to their
callers.

`debug_snapshot()` exposes lightweight diagnostic state, including error count,
last error message, dropped diagnostic count, wakeup state, and timer wakeup
hint state.

## Limits Contract

`RuntimeSessionLimits` only limits `vjsx` facade state. It does not limit the
QuickJS heap, stack, Promise job queue, or underlying timer queue.

Currently supported limits:

- `max_diagnostics`: maximum retained diagnostics. Older diagnostics are dropped
  when the ring buffer is full.
- `max_timer_wakeup_hints`: maximum retained timer wakeup hints. `0` means
  unlimited and is the default.
- `max_observations`: maximum retained structured turn observations. Recording
  never invokes host code on the turn's hot path; old observations are dropped
  and counted when the buffer is full.

`RuntimeEngineLimits` applies the actual QuickJS memory, stack and GC limits and
defines an optional default timeout for `run_turn(...)`. `memory_usage()` and
`debug_snapshot()` expose QuickJS's measured allocator and heap state.

## Turn And Lifecycle Contract

`RuntimeSession.run_turn(...)` is the managed entry point for hosts that need
production lifecycle guarantees. It rejects concurrent, draining, poisoned and
closed sessions; applies the configured deadline; and records duration, queue
wait and memory before/after the turn.

The visible phases are `ready`, `running`, `draining`, `poisoned`, and `closed`.
An interrupted runtime becomes `poisoned` and must be closed. `begin_drain()`
stops new turns while allowing the current owner to finish.

`runtimejs.SessionLane` adds thread-safe serialization and bounded admission.
Creating a lane transfers ownership of the session to it. Callers must no
longer enter the old `RuntimeSession` copy directly.

The operational guide and migration checklist are documented in
[Managed Runtime Hosting](MANAGED_RUNTIME_HOSTING.md).

## Profile Contract

Runtime capabilities are layered:

- `install_runtime_globals(...)` installs reusable globals such as `Buffer`,
  `URL`, `EventTarget`, and `AbortController`.
- `install_node_compat(...)` installs Node-like host capabilities and modules.
- `install_script_runtime(...)` is a lightweight script profile. Its direct
  `sqlite` and `mysql` modules are opt-in, and embedders can disable
  `path`/`os`/`process` when evaluating untrusted code.
- `install_node_runtime(...)` is the fuller Node-style profile.

`runtime_profile_snapshot(ctx)` returns the actual installed capability state.
It detects globals with `typeof` and modules through the `Context` module
registry. It does not import modules for detection.

The module registry is updated when `ctx.js_module(name).create()` succeeds.
Use:

```v
snapshot := vjsx.runtime_profile_snapshot(ctx)
snapshot.matches(.node)
snapshot.missing_for(.node)
snapshot.infer_kind()
ctx.runtime_modules()
```

Profile kind inference is intended for diagnostics and tests. Hosts should still
install the profile they need explicitly.

## Runtime Asset Contract

Runtime JavaScript and TypeScript support files are `vjsx` implementation
details. Embedders should depend on the public `vjsx` / `runtimejs` APIs, not on
the repository layout or a copied `thirdparty` tree.

The loading boundary is:

- Source ownership lives in `vjsx`.
- Release binaries embed the runtime assets they need to run JS/TS entries.
- `VJSX_ASSET_ROOT` and `ContextConfig.asset_root` are development override
  hooks only. They may replace an asset while developing, but production must
  not require them.
- If an override file is absent, the embedded asset is the source of truth.

The embedded runtime asset set includes the Web/Node compatibility files under
`web/js/` and the TypeScript runtime files:

- `thirdparty/typescript/lib/typescript.js`
- `thirdparty/typescript/lib/vjs_ts_bootstrap.js`
- `thirdparty/typescript/lib/vjs_ts_scan.js`
- `thirdparty/typescript/lib/vjs_ts_commonjs.js`
- `thirdparty/typescript/lib/vjs_ts_resolver.js`

`thirdparty/typescript/lib/typescript.js.gz` is a generated binary-size helper
for embedding. It is not a separate runtime contract; callers still request the
logical asset path `thirdparty/typescript/lib/typescript.js`.

Third-party license and version records must remain in the vendored source tree:

- `thirdparty/typescript/package.json`
- `thirdparty/typescript/LICENSE.txt`
- `thirdparty/typescript/VERSION`

Tests should cover both the asset registry and the release-style behavior where
`asset_root` points at an empty or incomplete directory and `.ts` / `.mts`
entries still run from embedded assets.

## Host Integration Guidance

Hosts should:

- keep one clear owner for each `RuntimeSession`
- call runtime pump APIs only from the owning lane/thread
- use wakeup `generation` to ignore stale scheduled wakeups
- pass worker code only async completion ports/cancel tokens, never Context or Value
- honor `async_ready_fn` by enqueueing `deliver_wakeup(0)` on the owning lane
- treat a false stream `try_push()` as backpressure and pause/retry production
- log or emit `RuntimeSessionDiagnostic` through `set_diagnostic_handler`
- inspect `debug_snapshot()` when reporting session health
- use `runtime_profile_snapshot(ctx)` to verify installed capabilities
- use `run_turn(...)` for managed execution, or `runtimejs.SessionLane` when
  callers can arrive from multiple threads
- configure `RuntimeEngineLimits` before loading untrusted or variable code

Hosts should not:

- maintain a second JS Promise job queue
- treat compatibility-mode timer wakeup hints as the source of timer truth
- call Promise resolve/reject or any QuickJS API from a background thread
- call lane-owned sessions from arbitrary caller threads
- use or close the old `RuntimeSession` copy after transferring it to a
  `runtimejs.SessionLane`
- change global `setTimeout` semantics to accept non-standard options
- rely on dynamic imports to probe installed modules
