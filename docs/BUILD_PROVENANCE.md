# Build Provenance and Reproducibility

Official vjsx archives are built only by the repository release workflow from a
Git tag whose version matches `v.mod`. V and quickjs-ng inputs are pinned by
immutable commits. Every release assembly contains SHA-256 checksums and GitHub
Actions generates signed SLSA build-provenance attestations for the five
archives and the checksum manifest.

Consumers can verify a downloaded archive against this repository with:

```sh
gh attestation verify vjsx-linux-x64.tar.gz --repo guweigang/vjsx
```

The equivalent command applies to the other platform archives and
`SHA256SUMS`.

## Reproducibility boundary

vjsx 1.0 promises traceable, pinned and attested official builds. It does not
promise that independently rebuilt native binaries or archives are bit-for-bit
identical. Compiler paths, platform SDKs, archive metadata and native toolchain
details can affect bytes without changing runtime behavior.

Reproducible-build improvements remain welcome, but they are tracked separately
from the 1.x compatibility contract. A rebuild must use the pinned V and
quickjs-ng revisions and should compare runtime/version smoke results, dynamic
dependencies and artifact ABI behavior in addition to checksums.
