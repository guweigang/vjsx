# Runtime Guarantees

This document states the runtime guarantees vjsx 1.x makes to embedders. These
guarantees apply when work enters QuickJS through `RuntimeSession.run_turn(...)`
or an owning `runtimejs.SessionLane` and the host follows the ownership and
scheduler contract in `RUNTIME_CONTRACT.md`.

Direct use of `Context`, raw `Value` handles, or manual event-loop pumping is an
advanced API. It remains supported, but the caller then owns the invariants that
the managed runtime normally enforces.

## Required Host Conditions

The guarantees below depend on the host doing all of the following:

- transfer a session to exactly one owner or `SessionLane`;
- route every QuickJS entry, wakeup, and Promise settlement through that owner;
- give worker threads only plain-data completion ports and cancellation tokens,
  never `Context` or `Value` handles;
- deliver the latest scheduled wakeup generation and tolerate cancellation of
  already queued wakeups;
- treat a poisoned session as terminal and close it instead of reusing it;
- apply process and OS isolation when JavaScript is hostile.

vjsx is an in-process runtime and cannot make an incorrect host scheduler,
unsafe native capability, or compromised embedding process safe.

## Single-Owner Execution

A managed `RuntimeSession` admits at most one turn at a time. Concurrent direct
turns are rejected before their action enters QuickJS. `SessionLane` serializes
callers from multiple V threads and bounds both its waiting queue and admission
wait when configured with non-zero limits.

Creating a `SessionLane` transfers ownership of the session to the lane. Using
the old session copy after that transfer violates the host contract.

## Lifecycle And Interruption

The managed lifecycle is `ready`, `running`, `draining`, `poisoned`, or
`closed`.

- Draining rejects new turns and allows the current owner to finish.
- A normal JavaScript exception completes the turn with an error but does not
  poison the session.
- A deadline or cancellation that interrupts QuickJS poisons the session.
- A poisoned session rejects later turns and must be closed.
- Closing a session more than once is safe.

vjsx does not forcibly free a runtime from a different thread while QuickJS or
a native host call is executing. Process-level hard deadlines remain the
embedder's responsibility.

## Async Host Boundary

Background workers cannot settle JavaScript Promises directly. A
`RuntimeHostAsyncCompletionPort` accepts only V-owned text or bytes and queues a
terminal event. The session owner later creates JavaScript values and settles
the Promise while draining the owning lane.

Completion, explicit cancellation, timeout, and session close share one
first-terminal-event gate. Exactly one terminal event wins; later submissions
return `false`. Closing settles and releases every pending Promise capability.
An operation with no earlier terminal event is rejected and its cancellation
token is marked cancelled; an already queued completion keeps its winning
outcome.

Wakeup requests carry a monotonically increasing generation. Delivery of an
obsolete non-zero generation is ignored without clearing or executing the
current wakeup.

## Bounded Admission And Backpressure

Configured session and lane limits reject excess work explicitly. They do not
silently drop turns. Host stream mailboxes return `false` when full; producers
must pause or retry after the owner drains capacity.

QuickJS heap, stack, garbage-collection threshold, and default turn deadline
are enforced only when the embedder configures the corresponding
`RuntimeEngineLimits`. Native allocations and blocking native calls are outside
the QuickJS heap and interrupt boundaries.

## Capabilities And Compatibility

JavaScript can use only capabilities installed by the selected runtime profile
and host policy. Unknown builtin module specifiers and incompatible artifact
profiles are rejected rather than silently installed or emulated.

Bytecode and bundle loading validates container format, artifact ABI, QuickJS
ABI, runtime profile, and checksum before evaluation. These checks detect
incompatibility and accidental corruption; they do not authenticate hostile
artifacts. Serialized artifacts remain trusted build outputs.

The exact supported Node, browser, TypeScript, package, and platform subsets
are defined by `SUPPORT_MATRIX.md` and `NODE_COMPATIBILITY.md`. A feature not
listed there is not implied by the presence of a similarly named API.

## Observability

Managed turns record bounded observations with outcome, duration, lane queue
wait, and QuickJS memory before and after execution. Debug snapshots expose
lifecycle, pending async work, wakeup state, rejection counters, diagnostics,
and memory accounting.

Observation and diagnostic buffers may drop their oldest entries when a finite
limit is reached. Dropped-record counters remain visible. Observability is not a
durability mechanism and is not retained after the session is closed.

## Explicit Non-Guarantees

vjsx 1.0 does not guarantee:

- distributed ownership, routing, leases, persistence, or recovery;
- persistent QuickJS heap snapshots or transparent session migration;
- hard termination of a blocking native call inside the embedding process;
- isolation between mutually hostile tenants in one process;
- complete Node.js, browser, npm, TypeScript, or Cloudflare Workers parity;
- authenticity of bytecode or bundles supplied by an untrusted party;
- automatic runtime pooling, hot replacement, or telemetry export.

Planned post-1.0 hosting work is described in `ROADMAP.md`. Roadmap items are
not part of the 1.0 compatibility contract.
