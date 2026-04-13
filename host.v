module vjsx

// Console log sink used by the host helpers.
pub type HostLogFn = fn (line string)

// HostConfig keeps the legacy host installation surface.
@[params]
pub struct HostConfig {
pub:
	console       bool = true
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
