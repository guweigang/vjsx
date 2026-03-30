# Embedding VJSX

This document focuses on the host-first embedding path:

- a V host exposes explicit capabilities to JS/TS
- JS/TS extensions call those host capabilities
- the V host loads JS/TS modules and plugins back through stable handles

This is the recommended direction when `vjsx` is embedded into another project.
It is intentionally narrower than "full Node compatibility".

## Goal

For most embedders, the practical target is:

1. create one managed session
2. install a formal host API
3. load one JS/TS file as an extension
4. call lifecycle hooks or exported functions from the host
5. close the session explicitly

That is enough for many extension systems. You do not need every lower-level
helper on day one.

If you want a concrete minimal example in this repository, start with:

- `examples/embedding_extension.v`
- `examples/js/host_extension.mjs`

If you want the next step up, with a host module and manifest-defined custom
hook names, see:

- `examples/embedding_extension_manifest.v`
- `examples/js/host_extension_manifest.mjs`

## Recommended Layers

### 1. `vjsx.RuntimeSession`

Use this when you need:

- explicit runtime/context ownership
- module loading
- direct export calls

This is the core lifecycle object.

### 2. `runtimejs.ExtensionSession`

Use this as the default embedder entrypoint.

It combines:

- a bridge-aware runtime session
- your installed host API
- bound host-context calls back into JS/TS

For most hosts, this should be the primary abstraction.

### 3. `runtimejs.ExtensionHandle`

Use this when one JS/TS file should behave like one extension instance.

It combines:

- lifecycle hooks: `activate(...)`, `handle(...)`, `dispose(...)`
- regular export calls: `call_export(...)`, `call_export_method(...)`,
  `call_default_method(...)`

If your host has a plugin model, this is usually the object you want to keep.

## Recommended Stopping Point

If you want to avoid over-design, stop here:

- `RuntimeSession` for lifecycle
- `ExtensionSession` for embedding
- `ExtensionHandle` for loaded extensions

That gives you a clear mental model without turning `vjsx` into a full plugin
platform framework.

## API Surface Guidance

Not every public helper should be treated as the same-level entrypoint.

### Default Host Path

These are the APIs that most embedders should reach for first:

- `runtimejs.new_node_extension_session(...)`
- `runtimejs.new_script_extension_session(...)`
- `ExtensionSession.load_extension(...)`
- `ExtensionHandle.activate(...)`
- `ExtensionHandle.handle(...)`
- `ExtensionHandle.dispose(...)`
- `ExtensionHandle.call_export(...)`
- `ExtensionHandle.call_export_method(...)`
- `ExtensionHandle.call_default_method(...)`

If your host can stay inside this set, that is usually a good sign.

### Core Building Blocks

These are still important, but they are better treated as lower-level
infrastructure than as the default everyday API:

- `vjsx.RuntimeSession`
- `RuntimeSession.import_module(...)`
- `RuntimeSession.load_plugin(...)`
- `ScriptModule`
- `ScriptPlugin`

They are useful when the host needs tighter control, but they should not be the
first abstraction most embedders see.

### Advanced Host-Context Helpers

These helpers are valid, but they are more specialized:

- `import_module_with_host(...)`
- `load_plugin_with_host(...)`
- `call_module_export_with_host(...)`
- `call_module_method_with_host(...)`
- `call_default_export_method_with_host(...)`

They exist mainly so higher-level abstractions can be built cleanly.
For a host-facing embedding API, prefer `ExtensionSession` and
`ExtensionHandle` over exposing these directly.

### Optional Metadata Layer

These are useful only when the host genuinely benefits from discovery or richer
contracts:

- `ExtensionSession.describe_extension(...)`
- JS/TS `export const extension = { ... }`
- manifest `services`
- `ExtensionHandle.call_service(...)`

This layer should stay optional. It is easy to over-invest in it too early.

## Stability Notes

The embedding-related API surface is not all equally important.

### Likely Long-Term Stable

These are the APIs that currently look like the right long-term host-facing
surface:

- `runtimejs.new_node_extension_session(...)`
- `runtimejs.new_script_extension_session(...)`
- `ExtensionSession`
- `ExtensionHandle`
- `vjsx.HostApiConfig`
- `vjsx.host_value(...)`
- `vjsx.host_object(...)`
- `vjsx.host_module_exports(...)`
- `vjsx.host_module_object(...)`

If another project embeds `vjsx`, this is the layer that should feel safest to
build around.

### Stable As Infrastructure

These are important and should remain solid, but they are better understood as
foundational building blocks than as the primary embedder API:

- `vjsx.RuntimeSession`
- `ScriptModule`
- `ScriptPlugin`
- `RuntimeSession.import_module(...)`
- `RuntimeSession.load_plugin(...)`
- `RuntimeSession.bind_plugin(...)`

Hosts may still use them directly, especially for custom integration work, but
they are not the best first abstraction for most projects.

### Public But Better De-Emphasized

These are useful internal composition helpers, yet they probably should not be
promoted as the main embedding path:

- `import_module_with_host(...)`
- `load_plugin_with_host(...)`
- `call_module_export_with_host(...)`
- `call_module_method_with_host(...)`
- `call_default_export_method_with_host(...)`

They are helpful because higher-level layers can be built on top of them
cleanly. That does not necessarily mean embedders should treat them as the
default API.

### Optional Contract Features

These features can be valuable, but they should stay clearly optional:

- `ExtensionSession.describe_extension(...)`
- JS/TS manifest metadata
- manifest `services`
- `ExtensionHandle.call_service(...)`

They are worth using when a host truly benefits from discovery and structured
contracts. They should not become mandatory ceremony for simple embedding.

## Suggested Documentation Posture

When documenting embedding, prefer this order:

1. `ExtensionSession`
2. `ExtensionHandle`
3. `HostApiConfig` and host builders
4. `RuntimeSession` for lower-level control
5. manifest and `services` only as optional enhancements

That ordering keeps the main story simple while still leaving room for advanced
integrations.

## Convergence Checklist

This is a practical cleanup checklist for future work. It is intentionally
about convergence, not feature expansion.

### Keep And Invest In

These are worth treating as the primary embedding surface:

- `runtimejs.new_node_extension_session(...)`
- `runtimejs.new_script_extension_session(...)`
- `runtimejs.ExtensionSession`
- `runtimejs.ExtensionHandle`
- `vjsx.HostApiConfig`
- `vjsx.host_value(...)`
- `vjsx.host_object(...)`
- `vjsx.host_module_exports(...)`
- `vjsx.host_module_object(...)`

For these APIs, the preferred work is:

- improve examples
- improve docs
- tighten lifecycle guarantees
- add focused tests around real embedder flows

### Keep But Lower The Visibility

These are still useful, but they should gradually move out of the "main story"
in docs and examples:

- `vjsx.RuntimeSession`
- `ScriptModule`
- `ScriptPlugin`
- `RuntimeSession.import_module(...)`
- `RuntimeSession.load_plugin(...)`
- `RuntimeSession.bind_plugin(...)`

For these APIs, the preferred work is:

- keep them correct
- keep them tested
- mention them as lower-level tools
- avoid making them the first thing new embedders see

### Treat As Composition Helpers

These APIs are useful for internal layering, but they should not become the
recommended path unless a host has a specific need:

- `import_module_with_host(...)`
- `load_plugin_with_host(...)`
- `call_module_export_with_host(...)`
- `call_module_method_with_host(...)`
- `call_default_export_method_with_host(...)`

For these APIs, the preferred work is:

- preserve behavior
- avoid expanding the family unless clearly needed
- document them as advanced helpers, not the default surface

### Keep Optional

These features should remain opt-in:

- `ExtensionSession.describe_extension(...)`
- JS/TS manifest metadata
- manifest `services`
- `ExtensionHandle.call_service(...)`

For these APIs, the preferred work is:

- keep syntax lightweight
- avoid mandatory ceremony
- resist turning them into a full declarative plugin framework too early

### Avoid For Now

These directions are the easiest ways to make the design too heavy too early:

- adding more parallel wrapper types for the same concepts
- making manifest metadata required for ordinary extension loading
- expanding `services` into a large schema system before real host demand exists
- documenting low-level helpers and high-level helpers as if they had equal
  priority
- treating Node compatibility as the architecture instead of as support tooling

## Suggested Next Code Cleanup

If code cleanup starts later, the likely order should be:

1. keep the current API surface stable
2. strengthen examples around `ExtensionSession` and `ExtensionHandle`
3. reduce documentation emphasis on lower-level duplicate paths
4. only then consider renames, moves, or soft deprecation notes

That sequence keeps current users safe while gradually making the public story
simpler.

## Host API Shape

Prefer exposing a small, explicit host API instead of many globals.

Useful building blocks:

- `vjsx.host_value(...)`
- `vjsx.host_object(...)`
- `vjsx.host_module_exports(...)`
- `vjsx.host_module_object(...)`
- `ctx.install_host_api(...)`

Typical pattern:

```v
import runtimejs
import vjsx

fn host_api() vjsx.HostValueBuilder {
	return vjsx.host_object(
		vjsx.HostObjectField{
			name:  'app'
			value: vjsx.host_object(
				vjsx.HostObjectField{
					name:  'name'
					value: vjsx.host_value('demo-host')
				},
			)
		},
		vjsx.HostObjectField{
			name:  'logger'
			value: vjsx.host_object(
				vjsx.HostObjectField{
					name:  'prefix'
					value: vjsx.host_value('log')
				},
			)
		},
	)
}

fn host_config() vjsx.HostApiConfig {
	return vjsx.HostApiConfig{
		globals: [
			vjsx.HostGlobalBinding{
				name:  'appName'
				value: vjsx.host_value('demo-host')
			},
		]
	}
}

fn main() {
	mut extension_session := runtimejs.new_node_extension_session(
		vjsx.ContextConfig{},
		vjsx.NodeRuntimeConfig{
			process_args: ['inline.js']
		},
		host_config(),
		host_api(),
	)
	defer {
		extension_session.close()
	}
}
```

## Loading Extensions

The main host flow is:

```v
mut extension := extension_session.load_extension('./extensions/search.mjs',
	vjsx.ScriptPluginHooks{}) or { panic(err) }
defer {
	extension.close()
}

activate := extension.activate('boot') or { panic(err) }
activate.free()

result := extension.call_export('search', 'hello') or { panic(err) }
defer {
	result.free()
}
```

This keeps the host-facing API simple:

- the host owns one session
- each loaded file becomes one extension handle
- the host can use lifecycle hooks and regular exports from the same handle

## JS/TS Manifest

Manifest support is optional.

An extension can declare metadata directly in JS/TS:

```js
export const extension = {
  name: "search-extension",
  capabilities: ["search", "index"],
  hooks: {
    activate: "boot",
    handle: "run",
    dispose: "teardown",
  },
};
```

Host-side behavior:

- `extension_session.describe_extension(path)` reads the manifest
- `extension_session.load_extension(path, vjsx.ScriptPluginHooks{})` uses the
  declared hook names automatically
- V-side `ScriptPluginHooks` still work as overrides

This is useful metadata, but it should stay lightweight.

## Services

Manifest `services` support exists, but treat it as optional.

It is useful when:

- the host wants stable service names
- you do not want raw export names spread across the embedding code

It is not required for a healthy first embedding design. If plain
`call_export(...)` and `call_export_method(...)` are enough, keep using those.

## Practical Guidance

Prefer:

- explicit host APIs
- explicit `session.close()`
- one extension file -> one `ExtensionHandle`
- a small manifest with only the metadata you actually need

Be careful about:

- leaking runtimes or contexts in long-lived processes
- adding too many parallel abstractions before the host's real needs are clear
- turning Node-compat helpers into the main architecture

## Current Recommendation

If you are embedding `vjsx` into another project today, start with:

1. `runtimejs.new_node_extension_session(...)` or
   `runtimejs.new_script_extension_session(...)`
2. `ctx.install_host_api(...)` through `HostApiConfig`
3. `extension_session.load_extension(...)`
4. `ExtensionHandle.activate(...)` / `call_export(...)` / `dispose(...)`

Only add manifest-level `services` or other richer contracts when the host
really benefits from them.
