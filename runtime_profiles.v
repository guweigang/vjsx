module vjsx

// ScriptRuntimeConfig describes a lightweight script-oriented runtime.
// It keeps console/path/process and small reusable globals, but skips `fs`.
@[params]
pub struct ScriptRuntimeConfig {
pub:
	fs_roots     []string
	process_args []string
	asset_root   string
	fetch        bool               = true
	fetch_config FetchGlobalsConfig = FetchGlobalsConfig{}
	log_fn       HostLogFn          = default_host_log
	error_fn     HostLogFn          = default_host_error
}

// NodeRuntimeConfig describes a fuller Node-like runtime profile.
@[params]
pub struct NodeRuntimeConfig {
pub:
	fs_roots     []string
	process_args []string
	asset_root   string
	fetch        bool               = true
	fetch_config FetchGlobalsConfig = FetchGlobalsConfig{}
	log_fn       HostLogFn          = default_host_log
	error_fn     HostLogFn          = default_host_error
}

// Install a lightweight script runtime profile.
pub fn (ctx &Context) install_script_runtime(config ScriptRuntimeConfig) {
	ctx.install_node_compat(NodeCompatConfig{
		fs:            false
		http:          false
		https:         false
		fetch:         config.fetch
		child_process: false
		runtime:       runtime_globals_minimal()
		fs_roots:      config.fs_roots
		process_args:  config.process_args
		asset_root:    config.asset_root
		fetch_config:  config.fetch_config
		log_fn:        config.log_fn
		error_fn:      config.error_fn
	})
	ctx.set_runtime_profile('script')
}

// Install a fuller Node-like runtime profile.
pub fn (ctx &Context) install_node_runtime(config NodeRuntimeConfig) {
	ctx.install_node_compat(NodeCompatConfig{
		runtime:      runtime_globals_full()
		fetch:        config.fetch
		fs_roots:     config.fs_roots
		process_args: config.process_args
		asset_root:   config.asset_root
		fetch_config: config.fetch_config
		log_fn:       config.log_fn
		error_fn:     config.error_fn
	})
	ctx.set_runtime_profile('node')
}

// Record the host runtime profile associated with this context. Runtime
// installers call this so bytecode artifacts can be rejected before QuickJS
// sees bytecode compiled for a different host contract.
pub fn (ctx &Context) set_runtime_profile(profile string) {
	mut target := unsafe { ctx }
	target.runtime_profile = profile.trim_space()
}

// Return the host runtime profile associated with this context.
pub fn (ctx &Context) runtime_profile() string {
	return ctx.runtime_profile
}
