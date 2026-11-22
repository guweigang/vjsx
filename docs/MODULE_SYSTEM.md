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
| computed `import()` / `require()` | not statically resolvable | unchanged/unsupported by CJS wrapper | not bundled; `import()` may use an opt-in host source loader at runtime |
| Node builtin | classified as a builtin edge | specifier preserved | availability depends on runtime profile |

No new Node builtin surface is introduced by the graph resolver.

## Asynchronous dynamic imports

On quickjs-ng 0.18+, an embedder may install
`Context.install_dynamic_import_loader(...)`. The callback receives a
`DynamicImportRequest` and a thread-safe `DynamicImportCompletionPort`; it may
resolve JavaScript source or reject the request from a worker. vjsx queues the
completion and performs `JS_LoadModule` / `JS_FinishDynamicImport` only when
the owning lane drains dynamic-import events.

The loader is deliberately opt-in and source-only. It does not grant implicit
filesystem, package, or network access, and it does not change the static graph
or bundle format. Relative imports in returned source continue through the
normal module loader and therefore need sources available through the host's
chosen loading policy.

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

## Embedding with a relative module mirror

Hosts may call `runtimejs.build_runtime_module_entry_with_mirror_base(ctx, entry,
true, output_root, project_root)` to mirror project files relative to
`project_root`. This avoids duplicating long absolute Windows paths beneath the
output directory. Import rewrites and generated runtime support files use the
same mirror layout. Sources outside `project_root` retain the normal absolute
path mirror. The caller owns the output directory and must keep it available
for deferred imports until execution finishes.
