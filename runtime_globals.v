module vjsx

// RuntimeGlobalsConfig controls the reusable non-host-specific JS globals.
@[params]
pub struct RuntimeGlobalsConfig {
pub:
	binary bool = true
	event  bool = true
	abort  bool = true
	timer  bool = true
	url    bool = true
}

// Full runtime globals preset.
pub fn runtime_globals_full() RuntimeGlobalsConfig {
	return RuntimeGlobalsConfig{}
}

// Minimal runtime globals preset for smaller non-host browser/node shims.
pub fn runtime_globals_minimal() RuntimeGlobalsConfig {
	return RuntimeGlobalsConfig{
		binary: true
		timer:  false
		url:    true
	}
}

// Install reusable runtime globals shared by higher-level host profiles.
pub fn (ctx &Context) install_runtime_globals(config RuntimeGlobalsConfig) {
	if config.binary {
		ctx.install_binary_globals()
	}
	if config.event {
		ctx.install_event_globals()
	}
	if config.abort {
		ctx.install_abort_globals()
	}
	if config.timer {
		ctx.install_timer_globals()
	}
	if config.url {
		ctx.install_url_globals()
	}
}
