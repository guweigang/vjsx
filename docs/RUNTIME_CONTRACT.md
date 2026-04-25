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

QuickJS resource controls remain the source of truth for engine-level limits,
such as stack size and memory limits.

## Profile Contract

Runtime capabilities are layered:

- `install_runtime_globals(...)` installs reusable globals such as `Buffer`,
  `URL`, `EventTarget`, and `AbortController`.
- `install_node_compat(...)` installs Node-like host capabilities and modules.
- `install_script_runtime(...)` is a lightweight script profile.
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

## Host Integration Guidance

Hosts should:

- keep one clear owner for each `RuntimeSession`
- call runtime pump APIs only from the owning lane/thread
- use wakeup `generation` to ignore stale scheduled wakeups
- log or emit `RuntimeSessionDiagnostic` through `set_diagnostic_handler`
- inspect `debug_snapshot()` when reporting session health
- use `runtime_profile_snapshot(ctx)` to verify installed capabilities

Hosts should not:

- maintain a second JS job queue
- treat timer wakeup hints as the source of timer truth
- call lane-owned sessions from arbitrary caller threads
- change global `setTimeout` semantics to accept non-standard options
- rely on dynamic imports to probe installed modules
