# Security Policy and Threat Model

vjsx embeds QuickJS in the host process. It is a capability-controlled runtime,
not an operating-system sandbox. A JavaScript crash, a native dependency bug,
or a capability implementation bug can affect the embedding process. Run
hostile code in a separately isolated process with OS resource and filesystem
controls.

## Trust boundaries

The embedder owns the runtime, its policy, host APIs, source resolution, and all
artifacts it loads. JavaScript may use every builtin and host API installed in
its context. Capability tags in extension manifests are descriptive metadata;
they do not grant or enforce access.

Use `host_policy_safe()` for extensions by default. It denies environment reads
and writes, subprocess and shell execution, filesystem reads and writes,
network access, `process.chdir`, and `process.exit`. The Node installer also
omits `fs`, `http`, `https`, `fetch`, `child_process`, `sqlite`, and `mysql` when
their underlying capability is denied.

`host_policy_trusted()` is the explicit compatibility preset. It grants the
historical full in-process host surface. `NodeRuntimeConfig{}`,
`ScriptRuntimeConfig{}`, `NodeCompatConfig{}`, and legacy `HostConfig{}` retain
that trusted default for source compatibility. New extension hosts should set a
policy explicitly.

## Filesystem and network boundaries

`HostPolicy.fs_read_roots` and `fs_write_roots` constrain the corresponding
operations when their grants are enabled. Existing paths are canonicalized;
new paths are resolved through their nearest existing parent. This blocks
ordinary absolute-path, traversal, and existing-symlink escapes, but does not
eliminate filesystem races. Use an OS sandbox when adversarial code can race
mounts, symlinks, or directory replacement.

`NodeCompatConfig.fs_roots` remains a legacy resolution mechanism: relative
reads search those roots and relative writes prefer the first root. By itself it
is not a security boundary. Only the policy roots are access boundaries.

`HostPolicy.network_hosts` is an exact hostname allowlist with optional
`*.example.com` subdomain patterns. An empty list means unrestricted hosts only
when `allow_network` is true. Automatic redirects are disabled when an allowlist
is present so a permitted origin cannot redirect into an unlisted host. This is
an application-layer check, not protection
against DNS rebinding or a compromised network stack; isolate hostile workloads
at the network/OS layer too.

## Trusted artifact input

QuickJS bytecode (`.qbc`) and vjsx bundles (`.vjsx`) are trusted build outputs,
not safe interchange formats for hostile input. Checksums detect accidental
corruption, not malicious construction or authenticity. Format, artifact ABI,
QuickJS ABI, and runtime-profile checks run before deserialization, but callers
must still authenticate provenance and load only artifacts from trusted builds.

The artifact ABI is independent of the vjsx product version. Historical format
1 artifacts whose compatibility field contains `0.0.x` migrate to artifact ABI
1; other unknown legacy lines and future ABI values are rejected. See
[`docs/API_STABILITY.md`](docs/API_STABILITY.md).

## Reporting

Report suspected vulnerabilities privately to the repository maintainers. Do
not include secrets, private artifacts, or production credentials in a public
issue.
