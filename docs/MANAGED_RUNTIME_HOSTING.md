# Managed Runtime Hosting

This guide explains the production-hosting layer built around
`vjsx.RuntimeSession`. It is for applications that keep QuickJS alive across
requests, execute variable or untrusted code, or accept calls from more than one
V thread.

The hosting layer is additive. Existing embedders can continue using
`RuntimeSession`, `Context`, and `ctx.eval(...)` directly. Adopting the managed
entrypoints adds explicit resource governance, lifecycle state, serialization,
and bounded observations without introducing distributed ownership or storage.

## What The Host Gains

| Concern | API | Guarantee |
| --- | --- | --- |
| QuickJS resources | `configure_engine_limits(...)` | Heap, stack, GC threshold, and default turn deadline |
| One JS entry | `run_turn(...)` | Lifecycle checks, deadline, memory/timing observation |
| Concurrent callers | `runtimejs.SessionLane` | One-at-a-time runtime entry and bounded admission |
| Health reporting | `debug_snapshot()` | Lifecycle, counters, diagnostics, and QuickJS memory |
| Turn reporting | `observations()` | Bounded polling records with outcome, latency, queue wait, and memory |
| Shutdown | `begin_drain()` / lane `close()` | Reject new work; a lane waits for its active turn before teardown |

QuickJS remains the owner of its heap, garbage collector, Promise job queue,
microtasks, and timers. The host remains the owner of scheduling, I/O policy,
persistence, and process-level containment.

## Recommended Baseline

Configure engine limits before loading variable code, and make `run_turn(...)`
the only entry into that session:

```v
import vjsx

fn evaluate_request(ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('40 + 2')
}

fn main() {
	mut session := vjsx.new_runtime_session(vjsx.ContextConfig{})
	session.configure_engine_limits(vjsx.RuntimeEngineLimits{
		memory_limit_bytes:      128 * 1024 * 1024
		max_stack_size_bytes:    2 * 1024 * 1024
		gc_threshold_bytes:      8 * 1024 * 1024
		default_turn_timeout_ms: 5_000
	})
	session.context().install_script_runtime(vjsx.ScriptRuntimeConfig{
		fetch:   false
		path:    false
		os:      false
		process: false
	})
	defer {
		session.close()
	}

	result := session.run_turn(vjsx.RuntimeSessionTurnOptions{
		kind: 'request'
	}, evaluate_request) or {
		if session.phase() == .poisoned {
			// Discard this session. Do not retry work on it.
		}
		panic(err)
	}
	defer {
		result.free()
	}
}
```

`timeout_ms` in `RuntimeSessionTurnOptions` overrides the configured default for
one turn. A zero value uses `default_turn_timeout_ms`; if both are zero, the turn
has no vjsx deadline.

## Engine Limits

`RuntimeEngineLimits` is applied to the QuickJS runtime itself:

- `memory_limit_bytes` sets the QuickJS allocator limit.
- `max_stack_size_bytes` sets the maximum QuickJS stack size.
- `gc_threshold_bytes` controls when QuickJS should run garbage collection.
- `default_turn_timeout_ms` supplies the default deadline for `run_turn(...)`.

Zero leaves the corresponding engine setting unchanged. Limits should normally
be configured once, immediately after session creation and before runtime
profiles, TypeScript, packages, or user modules are loaded.

These limits do not replace process containment. Native host calls may block in
code where the QuickJS interrupt handler cannot run, and native allocations are
not part of the QuickJS heap limit. Hosts executing adversarial workloads should
also enforce I/O timeouts and, where appropriate, a process-level deadline.

`memory_usage()` returns a stable V projection of QuickJS memory accounting.
The same memory record is included in `debug_snapshot()`.

## Turn Lifecycle

A managed session moves through these phases:

```text
ready -> running -> ready
          |          |
          |          +-> draining -> closed
          +-> poisoned -> closed
```

- `ready`: accepts one turn.
- `running`: rejects another direct turn.
- `draining`: rejects new turns while the current owner may finish.
- `poisoned`: execution was interrupted; the runtime must not be reused.
- `closed`: the runtime and context have been torn down.

A normal JavaScript exception returns an error but does not poison the session.
Cancellation or deadline interruption does poison it because QuickJS cannot be
assumed reusable after an interrupt. `clear_deadline()` cannot revive an
interrupted session.

After a poisoned result, close the session and create a new one. For sticky
kernels or plugin hosts, rebuild state by replaying trusted state or an
application-owned journal into the replacement session.

## Serialized Lanes

QuickJS runtimes must not be entered concurrently. When calls can arrive from
several threads, transfer the session to a `runtimejs.SessionLane`:

```v
import runtimejs
import vjsx

mut session := vjsx.new_runtime_session(vjsx.ContextConfig{})
session.configure_engine_limits(vjsx.RuntimeEngineLimits{
	memory_limit_bytes:      64 * 1024 * 1024
	default_turn_timeout_ms: 2_000
})
session.context().install_script_runtime(vjsx.ScriptRuntimeConfig{
	fetch:   false
	path:    false
	os:      false
	process: false
})

mut lane := runtimejs.new_session_lane(session, runtimejs.SessionLaneConfig{
	max_queue:         32
	admission_wait_ms: 500
})
defer {
	lane.close()
}

value := lane.run_turn(vjsx.RuntimeSessionTurnOptions{
	kind: 'extension.handle'
}, fn (ctx &vjsx.Context) !vjsx.Value {
	return ctx.eval('extension.handle()')
})!
defer {
	value.free()
}
```

Ownership transfers to the lane at `new_session_lane(...)`. The old session copy
must no longer be evaluated, pumped, drained, or closed directly. Use the lane
for all turns and close the lane at shutdown.

`max_queue` bounds waiting callers; zero means no queue-length limit.
`admission_wait_ms` bounds how long a caller waits for the turn gate. Admission
failure happens before JavaScript runs and does not poison the session. A zero
admission wait means fail fast when the gate is already occupied.

`SessionLane` provides in-process serialization, not distributed ownership.
Routing a session between machines, leasing, persistence, and recovery remain
application responsibilities.

## Shutdown

Call `lane.begin_drain()` when the host should stop accepting work. Calling
`lane.close()` also begins draining, waits for the current turn gate, and then
closes the owned session.

For a directly owned `RuntimeSession`, `begin_drain()` rejects new turns but does
not wait for a currently running turn. The host must join or otherwise wait for
that owner before calling `session.close()`.

## Observations And Diagnostics

Every completed managed turn records a `RuntimeSessionObservation` containing:

- session ID and host-defined turn kind
- outcome: `ok`, `error`, or `interrupted`
- start time and duration
- lane queue wait
- QuickJS memory before and after
- an error message when applicable

Observations are retained in a bounded ring configured through
`RuntimeSessionLimits.max_observations`. Recording does not invoke user or host
callbacks on the execution hot path. Poll with `observations()` and clear with
`clear_observations()`. Turns rejected before execution are represented by the
lifecycle and lane rejection counters rather than by turn observations. A zero
observation limit means unbounded retention; production hosts should normally
keep a finite limit.

Diagnostics and observations serve different purposes. Diagnostics describe
runtime facade failures; observations describe managed turns. `debug_snapshot()`
combines their counters with lifecycle and memory state for health endpoints and
support bundles.

## Capability Profiles

Resource limits do not create a security boundary by themselves. Embedders must
also install only the capabilities their code is allowed to use.

vjsx is an in-process embedder, not an operating-system sandbox. For fully
hostile code, combine least-privilege profiles with process isolation, OS-level
resource controls, and a process supervisor.

The lightweight script profile keeps `path`, `os`, and `process` enabled by
default for backwards compatibility, but each can be disabled through
`ScriptRuntimeConfig`. Direct `sqlite` and `mysql` modules are opt-in in the
script profile. The full Node profile remains intentionally broad.

For untrusted code, start with capabilities disabled and add host-owned APIs:

```v
runtimejs.new_script_runtime_session(vjsx.ContextConfig{}, vjsx.ScriptRuntimeConfig{
	fetch:   false
	path:    false
	os:      false
	process: false
})
```

In particular, do not expose `process` when the host process contains secrets in
its environment. Prefer a narrow V host API for database, filesystem, network,
and secret operations so policy remains in the embedding application.

## Migration From Direct Evaluation

Existing code:

```v
value := session.context().eval(source)!
```

Recommended migration:

1. Configure `RuntimeEngineLimits` immediately after creating the session.
2. Move the evaluation into a named `RuntimeSessionTurnFn`.
3. Replace direct evaluation with `session.run_turn(...)`.
4. If callers are concurrent, transfer the session to `SessionLane` and route
   every entry through `lane.run_turn(...)`.
5. Treat `.poisoned` as terminal and replace the session.
6. Poll observations and snapshots from host control code.
7. Add tests for timeout, queue-full, drain, capability absence, and replacement
   after interruption.

Code that continues to call `ctx.eval(...)` directly remains source-compatible,
but it does not receive turn admission, default deadlines, lifecycle counters,
or structured observations.

## Compatibility Notes

The managed hosting APIs are additive. Existing memory, stack, and GC setters
remain available, including their original parameter types. The byte-sized
variants and `RuntimeEngineLimits` avoid truncation for native-sized limits.

The script profile intentionally changed one accidental behavior: `sqlite` and
`mysql` are no longer installed unless requested. Embedders that deliberately
used those modules from a script profile must set `sqlite: true` or `mysql: true`,
or use the Node profile.

The URL compatibility implementation also follows standard relative-path and
query encoding behavior. Applications that depended on the previous incorrect
relative URL normalization should update their expectations.

## Non-Goals

The hosting layer deliberately does not implement:

- distributed runtime routing or leases
- persistent heap snapshots
- application state storage
- replacement of QuickJS Promise or timer queues
- policy for host database, filesystem, network, or secret APIs

Those concerns belong to the embedding application. vjsx provides a bounded,
observable, single-owner execution primitive on which those applications can
build.
