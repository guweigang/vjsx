module vjsx

// Console log sink used by the host helpers.
pub type HostLogFn = fn (line string)

@[params]
pub struct HostPolicy {
pub:
	allow_env_write bool
	allow_shell     bool
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
		allow_env_write: true
		allow_shell: true
	}
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
