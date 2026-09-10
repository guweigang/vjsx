module vjsx

import net.urllib

// Console log sink used by the host helpers.
pub type HostLogFn = fn (line string)

@[params]
pub struct HostPolicy {
pub mut:
	// Environment access is separate from exposing the rest of `process`.
	allow_env_read  bool
	allow_env_write bool
	// Direct argv-based execution and shell evaluation are separate grants.
	allow_subprocess bool
	allow_shell      bool
	// Filesystem grants are enforced in addition to NodeCompatConfig.fs_roots.
	// Empty boundary lists mean unrestricted access only when the corresponding
	// grant is enabled (the trusted compatibility preset).
	allow_fs_read  bool
	allow_fs_write bool
	fs_read_roots  []string
	fs_write_roots []string
	// Empty network_hosts means every host only when allow_network is true.
	allow_network       bool
	network_hosts       []string
	allow_process_chdir bool
	allow_process_exit  bool
}

// host_policy_safe denies host-side mutation and shell execution. This is the
// recommended policy for extensions that are not fully trusted.
pub fn host_policy_safe() HostPolicy {
	return HostPolicy{}
}

// host_policy_trusted preserves the historical, fully permissive host
// behavior. Only use it for code that is trusted as much as the embedder.
pub fn host_policy_trusted() HostPolicy {
	return HostPolicy{
		allow_env_read: true
		allow_env_write: true
		allow_subprocess: true
		allow_shell: true
		allow_fs_read: true
		allow_fs_write: true
		allow_network: true
		allow_process_chdir: true
		allow_process_exit: true
	}
}

fn policy_network_host_matches(host string, pattern string) bool {
	wanted := pattern.trim_space().to_lower()
	actual := host.trim_space().to_lower()
	if wanted == '' {
		return false
	}
	if wanted.starts_with('*.') {
		suffix := wanted[1..]
		return actual.ends_with(suffix) && actual.len > suffix.len
	}
	return actual == wanted
}

fn host_policy_allows_url(policy HostPolicy, raw_url string) ! {
	if !policy.allow_network {
		return error('network access is disabled')
	}
	if policy.network_hosts.len == 0 {
		return
	}
	parsed := urllib.parse(raw_url) or { return error('invalid network URL: ${raw_url}') }
	host := parsed.hostname()
	if host == '' {
		return error('network URL has no host: ${raw_url}')
	}
	for pattern in policy.network_hosts {
		if policy_network_host_matches(host, pattern) {
			return
		}
	}
	return error('network host is not allowed: ${host}')
}

// Check a URL against this policy without performing network I/O.
pub fn (policy HostPolicy) allows_network_url(raw_url string) bool {
	host_policy_allows_url(policy, raw_url) or { return false }
	return true
}

// HostConfig keeps the legacy host installation surface.
@[params]
pub struct HostConfig {
pub:
	console       bool = true
	crypto        bool = true
	fs            bool = true
	path          bool = true
	os            bool = true
	http          bool = true
	https         bool = true
	fetch         bool = true
	child_process bool = true
	process       bool = true
	sqlite        bool = true
	mysql         bool = true
	fs_roots      []string
	process_args  []string
	asset_root    string
	fetch_config  FetchGlobalsConfig = FetchGlobalsConfig{}
	policy        HostPolicy = host_policy_trusted()
	log_fn        HostLogFn = default_host_log
	error_fn      HostLogFn = default_host_error
}

fn default_host_log(line string) {
	println(line)
}

fn default_host_error(line string) {
	eprintln(line)
}

// Install a small reusable JS host into the current context.
// Prefer `install_node_compat` for new call sites.
pub fn (ctx &Context) install_host(config HostConfig) {
	ctx.install_node_compat(config.node_compat_config())
}
