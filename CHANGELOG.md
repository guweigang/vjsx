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
- npm tar extraction validates header checksums, octal fields, bounds, end
  markers and cross-platform traversal paths before writing files.

### Compatibility

- Existing panic-on-install constructors remain available as soft-deprecated
  wrappers. See `docs/UPGRADING.md`.
- Artifact ABI remains `vjsx-artifact-abi/1`; product version remains `0.0.8`.
