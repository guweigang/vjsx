module vjsx

// NodeCompatConfig describes the Node-like host capabilities exposed to JS.
@[params]
pub struct NodeCompatConfig {
pub:
	console       bool                 = true
	crypto        bool                 = true
	zlib          bool                 = true
	timers        bool                 = true
	fs            bool                 = true
	path          bool                 = true
	os            bool                 = true
	http          bool                 = true
	https         bool                 = true
	fetch         bool                 = true
	child_process bool                 = true
	process       bool                 = true
	sqlite        bool                 = true
	mysql         bool                 = true
	runtime       RuntimeGlobalsConfig = RuntimeGlobalsConfig{}
	fs_roots      []string
	process_args  []string
	asset_root    string
	fetch_config  FetchGlobalsConfig = FetchGlobalsConfig{}
	policy        HostPolicy         = HostPolicy{}
	log_fn        HostLogFn          = default_host_log
	error_fn      HostLogFn          = default_host_error
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
		crypto:        false
		zlib:          false
		fs:            false
		timers:        true
		http:          false
		https:         false
		fetch:         false
		child_process: false
		runtime:       runtime_globals_minimal()
		fs_roots:      fs_roots
		process_args:  process_args
	}
}

// Install a Node-like compatibility host into the current context.
pub fn (ctx &Context) install_node_compat(config NodeCompatConfig) {
	ctx.set_runtime_profile('node')
	if config.asset_root != '' {
		ctx.set_asset_root(config.asset_root)
	}
	if config.console {
		ctx.install_console(config.log_fn, config.error_fn)
	}
	ctx.install_runtime_globals(config.runtime)
	if config.timers {
		ctx.install_node_timers_promises_module()
	}
	if config.crypto {
		ctx.install_node_crypto_module()
	}
	if config.zlib {
		ctx.install_zlib_module()
	}
	if config.fetch {
		ctx.install_fetch_globals(config.fetch_config)
	}
	if config.fs {
		ctx.install_fs_module(config.fs_roots)
	}
	if config.path {
		ctx.install_path_module()
	}
	if config.os {
		ctx.install_os_module()
	}
	if config.http {
		ctx.install_http_module()
	}
	if config.https {
		ctx.install_https_module()
	}
	if config.child_process {
		ctx.install_child_process_module_config(ChildProcessModuleConfig{
			roots:       config.fs_roots
			allow_shell: config.policy.allow_shell
		})
	}
	if config.process {
		ctx.install_process_config(ProcessConfig{
			args:            config.process_args
			allow_env_write: config.policy.allow_env_write
		})
	}
	if config.sqlite {
		ctx.install_sqlite_module(config.fs_roots)
	}
	if config.mysql {
		ctx.install_mysql_module()
	}
}

fn (config HostConfig) node_compat_config() NodeCompatConfig {
	return NodeCompatConfig{
		console:       config.console
		crypto:        config.crypto
		fs:            config.fs
		path:          config.path
		os:            config.os
		http:          config.http
		https:         config.https
		fetch:         config.fetch
		child_process: config.child_process
		process:       config.process
		sqlite:        config.sqlite
		mysql:         config.mysql
		runtime:       RuntimeGlobalsConfig{}
		fs_roots:      config.fs_roots
		process_args:  config.process_args
		asset_root:    config.asset_root
		fetch_config:  config.fetch_config
		policy:        config.policy
		log_fn:        config.log_fn
		error_fn:      config.error_fn
	}
}
