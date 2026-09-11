module vjsx

// RuntimeGlobalsConfig controls the reusable non-host-specific JS globals.
@[params]
pub struct RuntimeGlobalsConfig {
pub:
	binary   bool = true
	event    bool = true
	abort    bool = true
	timer    bool = true
	url      bool = true
	encoding bool = true
	intl     bool = true
}

// Full runtime globals preset.
pub fn runtime_globals_full() RuntimeGlobalsConfig {
	return RuntimeGlobalsConfig{}
}

// Minimal runtime globals preset for smaller non-host browser/node shims.
pub fn runtime_globals_minimal() RuntimeGlobalsConfig {
	return RuntimeGlobalsConfig{
		binary: true
		timer: false
		url: true
		encoding: false
		intl: false
	}
}

// Install reusable runtime globals shared by higher-level host profiles.
pub fn (ctx &Context) try_install_runtime_globals(config RuntimeGlobalsConfig) ! {
	if config.binary {
		ctx.try_install_binary_globals()!
	}
	if config.event {
		ctx.try_install_event_globals()!
	}
	if config.abort {
		ctx.try_install_abort_globals()!
	}
	if config.timer {
		ctx.try_install_timer_globals()!
	}
	if config.url {
		ctx.try_install_url_globals()!
	}
	if config.encoding {
		ctx.try_install_encoding_globals()!
	}
	if config.intl {
		ctx.try_install_intl_globals()!
	}
}

// Install reusable globals using the legacy panic-on-install-failure contract.
// New embedders should use try_install_runtime_globals().
pub fn (ctx &Context) install_runtime_globals(config RuntimeGlobalsConfig) {
	ctx.try_install_runtime_globals(config) or { panic(err) }
}
