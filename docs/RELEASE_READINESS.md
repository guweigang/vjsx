# 1.0 Release-Readiness Audit

Audit baseline: `main` at `6554fa4`, current package version `0.0.8`.

## Strengthened in this phase

- Added recoverable runtime/profile/facade/lane installation APIs while keeping
  compatibility wrappers.
- Added deterministic truncation/property seeds for bytecode and bundle
  containers, package/tar/path seeds, module-cycle coverage, and async
  completion/cancellation/memory pressure loops.
- Added a curated JS/TS/package/profile corpus and an explicit support matrix.
- Added reproducible benchmark instructions without fragile CI latency gates.
- Pinned the V release used by CI, added release binary/version smoke checks,
  pinned QuickJS to an immutable commit, smoke-tested packaged archives, and
  generated checksums for all release archives.
- Documented API stability, migration, security boundaries, platform support,
  artifact ABI and release procedure.

## Remaining 1.0 blockers

1. Linux arm64 is release-smoked but not part of the pull-request test matrix.
2. Release archives are checksummed and extraction-smoked, but the workflow
   does not yet generate signed provenance/attestations. Bit-for-bit rebuilds
   are not demonstrated across all five platforms.
3. The low-level public `Runtime`/`Context`/`Value` surface is still broad and
   provisional. A 1.0 decision must either stabilize it or explicitly move it
   behind an advanced compatibility policy.
4. The selected package corpus is intentionally small. Real-package fixtures
   need owners, update policy and demonstrated coverage for every package named
   as supported.
5. The full matrix and benchmark baseline must pass on release infrastructure;
   local macOS evidence alone is insufficient.
6. V 0.5.2's experimental V3 type checker crashes while compiling the curl
   cancellation test. CI therefore selects V's bundled `-old-compiler`
   compatibility path; 1.0 should not depend on that workaround indefinitely.

## Version recommendation

Do not tag `1.0.0` yet. Continue the `0.x` line until the blockers above are
closed with CI/release evidence. No version number was changed by this audit.
