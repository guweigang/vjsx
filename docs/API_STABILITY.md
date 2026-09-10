# v0.1 API Stability

The v0.1 contract uses three stability levels.

## Stable embedder surface

These are the recommended APIs for extension hosts. Compatible additions are
allowed during v0.1; breaking changes require a documented migration and a
versioned release boundary.

- `runtimejs.ExtensionSession` and its node/script constructors
- `runtimejs.ExtensionHandle`
- `vjsx.HostPolicy`, `host_policy_safe()`, and `host_policy_trusted()`
- `vjsx.HostApiConfig` and the host value/module builders
- `vjsx.artifact_abi`, `BundleInfo.runtime_abi`, and trusted artifact loading

## Stable infrastructure

`vjsx.RuntimeSession`, `ScriptModule`, `ScriptPlugin`, managed turns, limits,
lanes, and observations are supported building blocks. They remain public, but
documentation does not present them as a peer default to `ExtensionSession`.

## Advanced or provisional

Manual `Runtime`/`Context` ownership, direct builtin installers, `_with_host`
composition helpers, extension manifest services, and incomplete Node
compatibility subsets may evolve during v0.1. Changes should remain source
compatible where practical and must be called out in release notes.

## Artifact compatibility

Container format versions describe byte layout. `artifact_abi` describes vjsx
serialization semantics. The QuickJS ABI fingerprint describes engine/build
compatibility. Runtime profiles describe the expected JS host surface. A load
succeeds only when all four layers are compatible; the vjsx product patch
version is informational and does not invalidate an artifact.

Format-1 artifacts emitted before this contract stored a product version where
the runtime ABI now lives. Values in the historical `0.0.x` line are treated as
artifact ABI 1, subject to QuickJS ABI and runtime-profile checks. Unknown
legacy lines and future ABI values are rejected and must be rebuilt.
