# Public API Inventory and Stability

This inventory defines the compatibility boundary for vjsx 1.x. Public V
visibility is necessary for modules inside this repository to cooperate, but it
does not by itself place a symbol in the stable 1.x contract. Every public
symbol belongs to one of the tiers below.

## Compatibility tiers

- **Stable**: the symbols in the recommended stable surface table follow
  semantic versioning throughout 1.x. Compatible additions are allowed;
  removals and incompatible behavior changes require the next major version.
- **Compatibility**: legacy entry points remain available throughout 1.x, but
  new code should use their documented replacements. They may receive only
  correctness and security fixes.
- **Advanced**: the low-level and provisional surfaces listed below are
  supported for expert embedders but are outside the 1.x source-compatibility
  guarantee. They may change in a minor release when QuickJS, safety, or
  lifecycle correctness requires it. Every such change requires a changelog
  entry and migration notes.

Unlisted public symbols are Advanced. A symbol becomes Stable only through an
explicit update to this inventory. This keeps the contract auditable even
though the V module exposes implementation-building blocks used by
`runtimejs`.

## Recommended stable surface

| Area | Public API | Stability |
| --- | --- | --- |
| Extension hosting | `runtimejs.ExtensionSession`, `ExtensionHandle`, `try_new_script_extension_session()`, `try_new_node_extension_session()` | stable |
| Managed sessions | `vjsx.RuntimeSession`, `try_new_script_runtime_session()`, `try_new_node_runtime_session()` | stable |
| Serialized ownership | `runtimejs.SessionLane`, `try_new_script_session_lane()`, `try_new_node_session_lane()` | stable |
| Host capabilities | `HostPolicy`, `host_policy_safe()`, `host_policy_trusted()`, `HostApiConfig`, host value/module builders | stable |
| Module handles | `ScriptModule`, `BoundScriptModule`, `ScriptPlugin`, `BoundScriptPlugin` | stable |
| Lifecycle and limits | managed turns, cancellation, observations, diagnostics, scheduler and engine/session limits | stable |
| Artifacts | `compile_module()`, `compile_bundle()`, `bundle_info()`, `load_bytecode()`, `load_bundle()`, `pack_app_executable()`, `read_appended_bundle()` | stable, trusted input only |
| Compatibility identity | `version`, `artifact_abi`, `artifact_abi_version`, `BundleInfo` | stable |

Public structs used as configuration or snapshots may gain fields with defaults.
Callers should use named fields and must not depend on undocumented field order.

## Compatibility wrappers (soft-deprecated)

The non-`try_` profile, extension, and lane constructors and the `install_*`
runtime-global/profile functions remain source-compatible. They preserve the
historical panic-on-install-failure behavior. New and migrating embedders should
use their `try_*` counterparts so missing or invalid runtime assets are ordinary
recoverable errors. No removal is scheduled before a documented major-version
boundary.

`HostConfig`/`install_host()` remain compatibility aliases for
`NodeCompatConfig`/`install_node_compat()`. New code should use the latter, or
prefer the higher-level extension/session constructors.

## Stable infrastructure, but not the default entry point

`RuntimeSession` bridges, `RuntimeHostAsyncOperation`, wakeup scheduling,
stream mailboxes, memory snapshots and direct module/plugin handles are
supported building blocks for hosts that need them. They require explicit
single-lane ownership and lifecycle discipline described in
`RUNTIME_CONTRACT.md`.

## Advanced or provisional

- Manual `Runtime`/`Context` ownership and raw `Value`/`Atom`/`Module` APIs.
- Direct individual builtin installers and `_with_host` composition helpers.
- Extension manifest service metadata.
- The incomplete Node compatibility subsets beyond behavior explicitly listed
  in `SUPPORT_MATRIX.md` and `NODE_COMPATIBILITY.md`.
- Low-level C/QuickJS-facing types and compile flags.

These APIs remain public for existing users, but they are in the Advanced tier
and are not covered by the 1.x source-compatibility guarantee. Changes should
remain source compatible where practical and must be called out in
`CHANGELOG.md` with migration guidance.

## 1.x change policy

- Patch releases contain compatible fixes only across all tiers unless a
  security or memory-safety issue makes that impossible.
- Minor releases may add Stable APIs and may evolve Advanced APIs with
  migration notes.
- Stable removals or incompatible Stable behavior changes require 2.0.
- Artifact compatibility is governed separately by the versioned artifact and
  QuickJS ABI checks below; product SemVer is not used as an artifact decoder
  switch.

## Error model

Filesystem, parsing, module resolution, compilation, artifact compatibility,
runtime-asset installation, cancellation and JS execution failures are
recoverable and should flow through V `!` results on the recommended surface.
Panics are reserved for compatibility wrappers, impossible internal invariants,
or failure to allocate the underlying runtime. JavaScript exceptions are
reported as `JSError`; session interruption uses `RuntimeInterruptedError`.

If a `try_install_*` call fails, its context may be partially configured and
must be closed rather than reused. Fallible session/facade constructors perform
that cleanup before returning the error.

## Artifact compatibility

Container format versions describe byte layout. `artifact_abi` describes vjsx
serialization semantics. The QuickJS ABI fingerprint describes engine/build
compatibility. Runtime profiles describe the expected JS host surface. A load
succeeds only when all four layers are compatible; the vjsx product patch
version is informational and does not invalidate an artifact.

Format-1 artifacts emitted before this contract stored a product version where
the runtime ABI now lives. Values in the historical `0.0.x` line are treated as
artifact ABI 1, subject to QuickJS ABI and runtime-profile checks. Unknown
legacy lines and future ABI values are rejected and must be rebuilt. See
`ARTIFACT_ABI.md` for the complete decision table.
