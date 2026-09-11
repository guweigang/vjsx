# Support Matrix

vjsx provides three intentionally bounded runtime profiles. This matrix is a
compatibility contract, not a promise of full Node.js, browser, npm, or
TypeScript compatibility.

## Platforms

| Platform | CI | Release artifact | Status |
| --- | --- | --- | --- |
| Linux x64 | test + release smoke | `vjsx-linux-x64.tar.gz` | supported |
| Linux arm64 | test + release smoke | `vjsx-linux-arm64.tar.gz` | supported |
| macOS x64 | test + release smoke | `vjsx-darwin-x64.tar.gz` | supported |
| macOS arm64 | test + release smoke | `vjsx-darwin-arm64.tar.gz` | supported |
| Windows x64 | test + release smoke | `vjsx-windows-x64.zip` | supported |
| Other OS/architectures | none | none | source-build only, unsupported |

The CI toolchain is pinned by `.v-version`; quickjs-ng is pinned by the immutable
commit in `.quickjs-version`. Release smoke checks verify the CLI,
reported version, runtime profile, script execution, bundle/app packaging and
the packaged executable. Release builds select V's OpenSSL crypto backend;
OpenSSL is therefore a source-build dependency for the advertised WebCrypto
ECDSA subset. Release smoke tests exercise ECDSA sign/verify on every artifact.

## Runtime profiles

| Capability | `node` | `script` | `browser` |
| --- | --- | --- | --- |
| Standard ECMAScript / modules | supported | supported | supported |
| JS and TypeScript entry/module graph | supported | supported | supported |
| `process`, `path`, `os` | supported subset | supported subset by default | rejected/absent |
| `Buffer`, URL, events, abort | supported subset | supported subset | supported subset |
| timers | supported subset | absent by default | supported subset |
| `fetch` | supported subset when policy allows | supported subset when policy allows | supported subset |
| `fs`, HTTP(S), child process | supported subset when policy allows | absent by default | rejected/absent |
| Node crypto/zlib | supported subset | absent | browser WebCrypto subset instead |
| sqlite/mysql compatibility modules | conditional, trusted policy only | opt-in legacy subset | absent |
| DOM rendering/layout/storage/workers | absent | absent | absent |

“Supported subset” means only the APIs documented in
`NODE_COMPATIBILITY.md`. Unknown builtin specifiers fail resolution; vjsx does
not silently install or emulate them.

## Source and package conformance

| Input | Status | Boundary |
| --- | --- | --- |
| `.js` / `.mjs` ESM | supported | static and dynamic-string imports in the reachable graph |
| `.ts` / `.mts` | supported subset | transpilation only; no type checking |
| `.cjs` / detected CommonJS | partial | statically discoverable `require()` and named-export interop |
| JSON modules | supported | generated default export |
| package `exports` root/subpath | supported subset | resolvable string targets used by the runtime graph |
| package `imports`, conditional matrices, loaders | partial or rejected | not Node-complete |
| computed `require()` / computed `import()` in bundles | rejected/not bundled | cannot be statically resolved |
| native addons (`.node`, `binding.gyp`) | rejected when reachable | no N-API/addon ABI |
| npm lifecycle scripts, arbitrary npm CLI behavior | rejected/not implemented | vjsx install is intentionally bounded |
| tar regular files/directories | supported | checksum, size and path validated before extraction |
| tar links, devices and special entries | ignored/rejected by capability | never materialized |

The curated executable corpus lives in `tests/conformance/` and is exercised by
`tests/conformance_test.v`. Parser seeds and truncation properties live beside
the bytecode, bundle, module-graph and package installer tests. Adding a support
claim requires a corpus case and a documented behavior.

Pinned third-party integrations and their ownership/update rules are listed in
[`PACKAGE_CONFORMANCE.md`](PACKAGE_CONFORMANCE.md). Those claims cover only the
versions and behavior exercised by their fixtures.
