# Release Checklist

## Source and contracts

- [ ] `CHANGELOG.md` has user-visible changes, migrations and known issues.
- [ ] `v.mod`, tag and `vjsx --version` agree; no version is inferred from branch names.
- [ ] Public API inventory and support matrix match exported behavior.
- [ ] Runtime guarantees match implementation, tests and documented host conditions.
- [ ] Artifact ABI changes, if any, include old/new fixtures and migration notes.
- [ ] Security review covers new host capabilities, parsers and dependencies.
- [ ] No unsupported Node builtin, database surface or parallel wrapper slipped in.

## Verification

- [ ] Run `v fmt -verify .` with the pinned `.v-version` toolchain.
- [ ] Run the full test matrix on Linux x64, macOS x64/arm64 and Windows x64.
- [ ] Confirm Linux arm64 passed both the regular matrix and release smoke.
- [ ] Run the conformance corpus and parser/property seeds.
- [ ] Run managed-runtime ownership, lifecycle, async race and stale-wakeup tests.
- [ ] Run release benchmarks on a named reference machine and compare medians.
- [ ] Distinguish repository failures from sandbox/network restrictions and V compiler defects.

## Artifacts and publishing

- [ ] Build only from the release tag and `.v-version`/`.quickjs-version` inputs.
- [ ] Verify CLI version, runtime smoke, bundle build/load and appended app execution.
- [ ] Inspect dynamic dependencies and include required Windows runtime DLLs.
- [ ] Confirm all five archives exist and publish `SHA256SUMS`.
- [ ] Verify checksums and confirm packaged-archive `--version`/runtime smoke passed.
- [ ] Verify signed provenance for all archives and `SHA256SUMS` with `gh attestation verify`.
- [ ] Confirm release notes link compatibility, security and migration guidance.

Do not change `v.mod` to `1.0.0` merely because this checklist exists. The
release-readiness audit must have no open 1.0 blockers.
