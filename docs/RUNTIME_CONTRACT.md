# vjsx Runtime Contract

This document records the current embedding contract for `vjsx` as a stable JS
runtime platform. It focuses on ownership boundaries: what QuickJS owns, what
`RuntimeSession` owns, and what the host must still provide.

## Ownership Boundary

QuickJS owns engine internals:

- JS heap and garbage collection
- stack limits and memory limits
- Promise jobs and microtasks
- the underlying `qjs:os` timer queue
- pending job execution through `JS_ExecutePendingJob`

`vjsx` owns session-level platform state:

- `RuntimeSession` lifecycle and idempotent close
- event-loop facade state
- timer wakeup hints for host scheduling
- diagnostic records and diagnostic handlers
- profile metadata and installed module registry
- optional limits for `vjsx` facade state

The host owns platform scheduling and I/O:

- choosing where a session runs
- delivering scheduled wakeups
- calling `pump_once()`, `drain_ready_tasks()`, or `pump_until_idle()` on the
  session-owning lane/thread
- implementing host I/O such as HTTP, DB, filesystem, sockets, and queues

The important rule is: **do not reimplement QuickJS queues in `vjsx` or the
host**. Reuse QuickJS for JS jobs and timers; use `RuntimeSession` only to
express host-facing wakeup and diagnostic state.

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
- `runtime_owned_timers` is metadata for future runtime-owned timer work; it
  does not mean `vjsx` currently replaces QuickJS timers.

`configure_event_loop(...)` also installs the timer wakeup bridge used by the
JS timer wrapper. Hosts should not call `install_timer_wakeup_bridge()` directly.

Wakeup requests include a monotonically increasing `generation`. Hosts should
store both `wake_at_ms` and `generation` and ignore stale wakeups whose pair no
longer matches the latest pending request.

For lane-owned runtimes, the caller thread should not touch the lane-owned
`RuntimeSession` directly. The host should enqueue work back to the owning lane
and pump the session there.

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

`node:timers/promises` supports `AbortSignal`. It is implemented on top of the
existing global `setTimeout` / `clearTimeout`, so QuickJS still owns the real
timer queue.

Timer wakeup hints are not timers. They are `vjsx` facade state that lets the
host schedule an efficient lane/session wakeup instead of polling.

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
- log or emit `RuntimeSessionDiagnostic` through `set_diagnostic_handler`
- inspect `debug_snapshot()` when reporting session health
- use `runtime_profile_snapshot(ctx)` to verify installed capabilities
- use `run_turn(...)` for managed execution, or `runtimejs.SessionLane` when
  callers can arrive from multiple threads
- configure `RuntimeEngineLimits` before loading untrusted or variable code

Hosts should not:

- maintain a second JS job queue
- treat timer wakeup hints as the source of timer truth
- call lane-owned sessions from arbitrary caller threads
- use or close the old `RuntimeSession` copy after transferring it to a
  `runtimejs.SessionLane`
- change global `setTimeout` semantics to accept non-standard options
- rely on dynamic imports to probe installed modules
