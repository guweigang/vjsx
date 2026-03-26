module vjsx

// NodeCompatConfig describes the Node-like host capabilities exposed to JS.
@[params]
pub struct NodeCompatConfig {
pub:
	console      bool = true
	fs           bool = true
	path         bool = true
	process      bool = true
	runtime      RuntimeGlobalsConfig = RuntimeGlobalsConfig{}
	fs_roots     []string
	process_args []string
	log_fn       HostLogFn = default_host_log
	error_fn     HostLogFn = default_host_error
}

// Full Node-like compatibility preset.
pub fn node_compat_full(fs_roots []string, process_args []string) NodeCompatConfig {
	return NodeCompatConfig{
		runtime:      runtime_globals_full()
		fs_roots:     fs_roots
		process_args: process_args
	}
}

// Minimal Node-like compatibility preset.
// Keeps console/path/process plus core runtime globals, but skips `fs`.
pub fn node_compat_minimal(fs_roots []string, process_args []string) NodeCompatConfig {
	return NodeCompatConfig{
		fs:           false
		runtime:      runtime_globals_minimal()
		fs_roots:     fs_roots
		process_args: process_args
	}
}

// Install a Node-like compatibility host into the current context.
pub fn (ctx &Context) install_node_compat(config NodeCompatConfig) {
	if config.console {
		ctx.install_console(config.log_fn, config.error_fn)
	}
	ctx.install_runtime_globals(config.runtime)
	if config.fs {
		ctx.install_fs_module(config.fs_roots)
	}
	if config.path {
		ctx.install_path_module()
	}
	if config.process {
		ctx.install_process(config.process_args)
	}
}

fn (config HostConfig) node_compat_config() NodeCompatConfig {
	return NodeCompatConfig{
		console:      config.console
		fs:           config.fs
		path:         config.path
		process:      config.process
		runtime:      RuntimeGlobalsConfig{}
		fs_roots:     config.fs_roots
		process_args: config.process_args
		log_fn:       config.log_fn
		error_fn:     config.error_fn
	}
}
