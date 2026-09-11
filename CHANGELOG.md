# Changelog

All notable user-visible changes are recorded here. This project has not yet
declared a 1.0 stability boundary.

## Unreleased

### Added

- Fallible `try_*` constructors/installers for managed runtime, extension and
  lane setup.
- Public API inventory, support matrix, artifact ABI guide, migration guide,
  release checklist and release-readiness audit.
- Curated JS/TS/package profile conformance corpus and release benchmark.
- Boundary/property seeds for artifact and npm tar/package parsers plus runtime
  cancellation and memory-pressure loops.
- Release archive checksums and binary/version consistency smoke checks.
- Signed release provenance, a release benchmark artifact, and pinned
  real-package conformance in CI.

### Changed

- `vjsx build` now copies the running `vjsx` executable and appends the bundle;
  release packages no longer include a separate `vjsx-app-runner` binary.
- Unix CI builds QuickJS once and links it into the test binaries, and the
  macOS arm64 test target now uses macOS 26.
- The public API contract now separates Stable, Compatibility and Advanced
  tiers for the 1.x compatibility boundary.
- Module graph discovery now uses the TypeScript syntax tree, preventing
  import-like text inside strings and comments from becoming false dependency
  edges.
- Unix release builds give the selected static libssl and libcrypto archives
  first priority in the compiler library search path and reject either dynamic
  OpenSSL dependency.
- Windows release builds reuse the pinned toolchain's V1 compatibility compiler
  directly, serialize MSVC cgen, and verify the final binary exists before the
  build step can succeed.
- CI uses the V version pinned by `.v-version` rather than a moving compiler.
- Release builds explicitly select V's OpenSSL backend and smoke-test WebCrypto
  ECDSA on every packaged platform.
- npm tar extraction validates header checksums, octal fields, bounds, end
  markers and cross-platform traversal paths before writing files.
- Crypto host failures are surfaced as JavaScript exceptions instead of process
  panics, and shared CLI tests recover abandoned build locks.
- Unix curl process management uses the platform `posix_spawn` type in an
  isolated C translation unit instead of assuming an opaque ABI layout.
- `child_process.fork()` reuses the running vjsx executable instead of invoking
  the source-tree wrapper and recompiling the CLI for every child.

### Compatibility

- Existing panic-on-install constructors remain available as soft-deprecated
  wrappers. See `docs/UPGRADING.md`.
- Artifact ABI remains `vjsx-artifact-abi/1`; product version remains `0.0.8`.
