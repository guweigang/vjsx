# Post-1.0 Runtime Hosting Roadmap

This document records likely vjsx 1.1 hosting work. It is planning guidance,
not a compatibility promise: names, ordering, and exact API shapes may change
after design and testing.

The 1.0 contract remains the bounded, observable, single-owner runtime defined
in `GUARANTEES.md`. Post-1.0 work should build above that primitive without
adding distributed storage or weakening owner-lane safety.

## 1.1 Priorities

### Host Contract Verification

Provide a conformance helper or executable fixture that an embedding
application can run against its scheduler integration. It should verify:

- wakeup scheduling, cancellation, and stale-generation handling;
- worker completion delivery back to the owning lane;
- first-terminal-wins across completion, cancellation, timeout, and close;
- queue-full and admission-timeout rejection;
- artifact/profile and installed-capability compatibility.

The verifier should diagnose violated host assumptions without taking ownership
of the application's scheduler.

### Safe Runtime Generations

Explore an optional `runtimejs` layer for replacing long-lived sessions:

1. construct and validate a new session beside the active generation;
2. attach a module-graph digest and runtime-profile identity;
3. atomically route new turns to the new generation;
4. drain and close the previous generation at a safe point;
5. expose generation identity in snapshots and observations.

This is replacement by reconstruction, not mutation or serialization of a live
QuickJS heap. Application state recovery remains host-owned.

### Bounded Drain Policy

Design a shutdown policy with separate admission, cancellation, no-progress,
and total deadlines. A soft deadline may cancel pending host operations and
poison the session. A hard deadline must report the owner as unhealthy for a
process supervisor; it must not free a running QuickJS context from another
thread.

### Deterministic Scheduler Testing

Make the runtime clock and scheduler easier to drive deterministically in tests.
Retain regression schedules for completion/cancel/timeout/close races, queued
turns racing drain, and stale wakeups. Expand differential fixtures against
Node.js or relevant Web Platform behavior when vjsx claims compatibility.

### Correlated Observations

Add sink-neutral correlation fields such as request, trace, operation, and
generation identifiers. Include host-async duration/outcome and queue high-water
state. Exporters, including a possible OpenTelemetry adapter, should live above
the core observation contract, be optional, and shed telemetry before runtime
work under pressure.

## Later 1.x Exploration

Consider an optional local runtime-residency policy for applications managing
many sessions. It may bound resident sessions, idle age, memory pressure, and
admission backlog, but may evict only at safe points. Journaling, replay, and
durable state remain application responsibilities.

This work should start as a policy/reference layer rather than making
`RuntimeSession` itself a distributed actor or process-wide singleton.

## Continuing Non-Goals

The roadmap does not include distributed leases, consensus, object-storage
coordination, database replication, persistent heap snapshots, Durable Objects,
Queues, Workflows, or transparent movement of a runtime between machines.
