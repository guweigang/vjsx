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

### Changed

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
