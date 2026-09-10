# Module Resolution, Emission, and Tooling

`runtimejs.resolve_module_graph(...)` is the shared module-resolution contract
for runtime loading, `check --json`, package compatibility checks, and project
bundles. Resolution happens before emission. The emitter consumes resolved
edges and does not silently retry or omit unresolved imports.

Each graph records the canonical entry, runtime profile, normalized tsconfig
hash, deterministic nodes and edges, and its compilation cache key. An edge
contains its importer, original specifier, resolved target, resolution phase,
module kind, and builtin status. Static-string `import()`, ESM imports and
exports, and static-string `require()` are included. Computed specifiers remain
a runtime concern and are not bundled.

## Compatibility matrix

| Input | Resolution | Emission | Runtime/bundle behavior |
| --- | --- | --- | --- |
| `.js` / `.mjs` | filesystem, tsconfig paths, self package, `node_modules` | ESM with rewritten resolved edges | supported |
| `.ts` / `.mts` | same graph resolver | TypeScript ESNext transform with inline source map | supported |
| `.cjs` / detected CommonJS | static `require()` edges | ESM interop wrapper with named exports and inline source map | supported for statically discoverable dependencies |
| `.json` | filesystem or package target | generated ESM default export | supported |
| package `exports` | package helper selects root/subpath target | target kind determines transform | supported for exported targets |
| static-string `import()` | included in graph | specifier rewritten | supported |
| computed `import()` / `require()` | not statically resolvable | unchanged/unsupported by CJS wrapper | not bundled |
| Node builtin | classified as a builtin edge | specifier preserved | availability depends on runtime profile |

No new Node builtin surface is introduced by the graph resolver.

## Cache contract

Emitted graphs are stored outside the source tree. `VJSX_CACHE_DIR` selects the
base directory; otherwise vjsx uses a user-keyed directory below the operating
system temporary directory. This replaces routine `<entry>.vjsbuild` trees.
Explicit temporary roots used by embedders and package staging remain supported.

The cache key includes:

- every reachable source path, kind, content hash, and resolved edge;
- the normalized tsconfig (including resolved `extends` input);
- runtime profile;
- vjsx artifact ABI;
- QuickJS implementation, version, pointer width, endianness, and bignum ABI.

Cache entries are immutable. They are emitted into a process-unique staging
directory, marked complete, and atomically moved into place. A source,
configuration, dependency resolution, profile, artifact ABI, or QuickJS ABI
change therefore selects a different entry rather than mutating an old one.

## Diagnostics and source locations

Resolution failures use this stable text envelope:

```text
[module-resolution] importer=... specifier="..." phase=... reason=...
```

`vjsx check --json` and `vjsx inspect --json` expose those fields separately for
tools. JSON check resolves and compiles the graph without evaluating user code,
so program output cannot corrupt its JSON stream. Plain `vjsx check` retains its
existing execute-and-report behavior.

TypeScript output and CommonJS wrappers contain standard inline source map v3
data with original sources. Runtime errors from cached modules are remapped to
the original source path and line; wrapper-only frames remain identified as
generated frames rather than being assigned a misleading source line.

## Inspection

```sh
vjsx inspect src/main.mts
vjsx inspect --json --runtime node src/main.mts
vjsx check --json --module src/main.mts
```

Inspection performs resolution only. It reports a deterministic graph and the
cache key that run/check/bundle use for the same inputs.
