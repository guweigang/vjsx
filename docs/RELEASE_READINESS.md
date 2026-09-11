# 1.0 Release-Readiness Audit

Audit baseline: `main` at `6945e7c`, current package version `0.0.8`.

## Strengthened in this phase

- Added recoverable runtime/profile/facade/lane installation APIs while keeping
  compatibility wrappers.
- Added deterministic truncation/property seeds for bytecode and bundle
  containers, package/tar/path seeds, module-cycle coverage, and async
  completion/cancellation/memory pressure loops.
- Added a curated JS/TS/package/profile corpus and an explicit support matrix.
- Added reproducible benchmark instructions without fragile CI latency gates.
- Pinned the V revision used by CI, added release binary/version smoke checks,
  pinned QuickJS to an immutable commit, smoke-tested packaged archives, and
  generated checksums for all release archives.
- Documented API stability, migration, security boundaries, platform support,
  artifact ABI and release procedure.
- Promoted Linux arm64 into the pull-request test matrix and aligned macOS
  arm64 testing with the macOS 26 release target.
- Converged `vjsx build` on the running CLI executable, removing the separate
  app-runner build, package and version-sync surface.
- Prebuilt QuickJS once per CI job so the Unix matrix links the same static
  library into every test instead of recompiling the engine for each file.
- Defined the 1.x Stable, Compatibility and Advanced public API tiers. Public
  visibility alone no longer implies a SemVer guarantee.
- Added a pinned OpenAI SDK/AI SDK real-package fixture to the Ubuntu CI gate
  with explicit ownership and update rules.
- Added release archive/checksum provenance attestations and made manual
  release workflow dispatch non-publishing by default.
- Added a named-runner benchmark artifact to every release workflow run and
  documented that 1.0 promises pinned, attested builds rather than
  bit-for-bit-identical native rebuilds.

## Remaining 1.0 blockers

1. The updated pull-request matrix, benchmark job, archive assembly and signed
   attestation path must pass once on release infrastructure.
2. Publish `v1.0.0-rc.1` from the same pinned inputs and complete the release
   checklist against its downloadable artifacts before creating `v1.0.0`.
## Version recommendation

Do not tag `1.0.0` directly. Close the evidence gate, publish `v1.0.0-rc.1`, and
promote the same contracts to `v1.0.0` after the RC checklist passes. No version
number was changed by this audit.
