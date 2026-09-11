# 1.0 Release-Readiness Audit

Audit baseline: `main` at `28a4379`, release-candidate package version
`1.0.0-rc.1`.

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

## Release-infrastructure evidence

- The five-platform pull-request matrix passed on Linux x64/arm64, macOS
  x64/arm64 and Windows x64, including real-package installation smoke tests
  on macOS arm64 and Windows x64, in
  [run 34585825347](https://github.com/guweigang/vjsx/actions/runs/34585825347).
- A non-publishing release dry run built and smoke-tested all five archives,
  recorded the benchmark, assembled and revalidated `SHA256SUMS`, and generated
  signed provenance in
  [run 34588550508](https://github.com/guweigang/vjsx/actions/runs/34588550508).

## Remaining 1.0 blocker

Publish `v1.0.0-rc.1` from the same pinned inputs and complete the release
checklist against its downloadable artifacts before creating `v1.0.0`.

## Version recommendation

Do not tag `1.0.0` directly. Publish `v1.0.0-rc.1` and promote the same contracts
to `v1.0.0` only after the RC checklist passes.
