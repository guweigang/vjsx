# Upgrading and Migration

## Move to fallible constructors

Existing constructors remain compatible, but may panic if embedded runtime
assets cannot be installed:

```v
mut session := runtimejs.new_node_extension_session(...)
```

New code should use the fallible counterpart:

```v
mut session := runtimejs.try_new_node_extension_session(...) or {
  return error('failed to initialize JavaScript host: ${err.msg()}')
}
```

The same migration applies to node/script `RuntimeSession`, `ExtensionSession`,
`SessionLane`, runtime profile installers and individual runtime-global
installers. When a direct `try_install_*` call fails, close the context/session;
it may be partially configured. Fallible constructors already close failed
sessions.

## Make trust explicit

Historical profile defaults are trusted for source compatibility. Extension
hosts should pass `policy: vjsx.host_policy_safe()` and then enable only needed
capabilities and bounded roots/hosts. `fs_roots` controls resolution, not
security. See `SECURITY.md`.

## Rebuild serialized artifacts

Artifacts are portable only across matching container, artifact ABI, QuickJS
ABI and runtime profile. A vjsx package-version upgrade alone does not require a
rebuild, but a QuickJS/toolchain/profile mismatch does. Keep source inputs so
artifacts can always be regenerated.

## Node/package expectations

Do not treat the `node` profile or `vjsx install` as complete Node/npm. Audit
dependencies against `SUPPORT_MATRIX.md`, run `vjsx check --json`, and add the
package to the conformance corpus before claiming support.
