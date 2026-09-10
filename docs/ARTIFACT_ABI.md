# Artifact ABI Compatibility

`.qbc`, `.vjsx`, and appended application bundles are trusted build artifacts,
not safe hostile-input formats. The loader validates structure before handing
QuickJS bytecode to the engine, but checksums provide integrity only, not
authenticity. Distributors must publish and verify cryptographic checksums or a
stronger signature/provenance mechanism.

## Compatibility decision

| Layer | Compatible when | Failure behavior |
| --- | --- | --- |
| Container magic and format | exact supported format | rejected before deserialization |
| Section lengths/ranges | complete, non-overlapping, in bounds | rejected before allocation/load |
| SHA-256 checksum | exact match | rejected as corrupt |
| Artifact ABI | exact `vjsx-artifact-abi/1`, or mapped historical `0.0.x` format-1 value | rejected; rebuild required |
| QuickJS ABI | implementation, engine version, pointer width, endianness and bignum fingerprint match | rejected; rebuild required |
| Runtime profile | artifact profile equals target context profile | rejected; use matching profile/rebuild |
| Product version | informational | does not alone invalidate an artifact |

ABI changes require incrementing `artifact_abi_version`, updating
`artifact_abi`, adding old/new compatibility tests, documenting whether a
migration is possible, and adding a release-note entry. Never broaden the
historical `0.0.x` mapping to an unknown version line without fixtures from
artifacts actually emitted by that line.

Boundary tests cover every truncated prefix of representative bytecode and
bundle artifacts, corrupted checksums, format/profile/QuickJS/artifact ABI
mismatches, duplicate and invalid module ranges, and appended executable footer
validation. These are deterministic regression seeds, not proof that loading
malicious QuickJS bytecode is safe.
