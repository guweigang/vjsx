module vjsx

pub enum RuntimeProfileKind {
	unknown
	runtime_minimal
	script
	node_minimal
	node
}

pub struct RuntimeProfileSnapshot {
pub:
	has_abort_controller     bool
	has_abort_signal         bool
	has_event_target         bool
	has_url                  bool
	has_buffer               bool
	has_set_timeout          bool
	has_clear_timeout        bool
	has_fetch                bool
	has_process              bool
	has_node_timers_promises bool
	has_fs_module            bool
	has_path_module          bool
	has_http_module          bool
	has_https_module         bool
	has_os_module            bool
	has_child_process_module bool
	has_sqlite_module        bool
	has_mysql_module         bool
}

fn (kind RuntimeProfileKind) required_capabilities() []string {
	return match kind {
		.runtime_minimal {
			['AbortController', 'AbortSignal', 'EventTarget', 'URL', 'Buffer']
		}
		.script {
			[
				'AbortController',
				'AbortSignal',
				'EventTarget',
				'URL',
				'Buffer',
				'process',
				'path',
				'node:timers/promises',
			]
		}
		.node_minimal {
			[
				'AbortController',
				'AbortSignal',
				'EventTarget',
				'URL',
				'Buffer',
				'process',
				'path',
				'node:timers/promises',
			]
		}
		.node {
			[
				'AbortController',
				'AbortSignal',
				'EventTarget',
				'URL',
				'Buffer',
				'process',
				'setTimeout',
				'clearTimeout',
				'node:timers/promises',
				'fs',
				'path',
				'http',
				'https',
			]
		}
		.unknown {
			[]string{}
		}
	}
}

pub fn (snapshot RuntimeProfileSnapshot) has_capability(name string) bool {
	return match name {
		'AbortController' { snapshot.has_abort_controller }
		'AbortSignal' { snapshot.has_abort_signal }
		'EventTarget' { snapshot.has_event_target }
		'URL' { snapshot.has_url }
		'Buffer' { snapshot.has_buffer }
		'setTimeout' { snapshot.has_set_timeout }
		'clearTimeout' { snapshot.has_clear_timeout }
		'fetch' { snapshot.has_fetch }
		'process' { snapshot.has_process }
		'node:timers/promises' { snapshot.has_node_timers_promises }
		'fs' { snapshot.has_fs_module }
		'path' { snapshot.has_path_module }
		'http' { snapshot.has_http_module }
		'https' { snapshot.has_https_module }
		'os' { snapshot.has_os_module }
		'child_process' { snapshot.has_child_process_module }
		'sqlite' { snapshot.has_sqlite_module }
		'mysql' { snapshot.has_mysql_module }
		else { false }
	}
}

pub fn (snapshot RuntimeProfileSnapshot) missing_for(kind RuntimeProfileKind) []string {
	required := kind.required_capabilities()
	mut missing := []string{}
	for capability in required {
		if !snapshot.has_capability(capability) {
			missing << capability
		}
	}
	return missing
}

pub fn (snapshot RuntimeProfileSnapshot) matches(kind RuntimeProfileKind) bool {
	return kind != .unknown && snapshot.missing_for(kind).len == 0
}

pub fn (snapshot RuntimeProfileSnapshot) infer_kind() RuntimeProfileKind {
	if snapshot.matches(.node) {
		return .node
	}
	if snapshot.matches(.script) && snapshot.has_fetch && !snapshot.has_fs_module
		&& !snapshot.has_set_timeout {
		return .script
	}
	if snapshot.matches(.node_minimal) && !snapshot.has_fetch && !snapshot.has_set_timeout {
		return .node_minimal
	}
	if snapshot.matches(.runtime_minimal) && !snapshot.has_process && !snapshot.has_set_timeout {
		return .runtime_minimal
	}
	return .unknown
}

fn runtime_profile_has_global(ctx &Context, expr string) bool {
	value := ctx.eval(expr) or { return false }
	defer {
		value.free()
	}
	return value.to_bool()
}

pub fn runtime_profile_snapshot(ctx &Context) RuntimeProfileSnapshot {
	return RuntimeProfileSnapshot{
		has_abort_controller:     runtime_profile_has_global(ctx, 'typeof AbortController === "function"')
		has_abort_signal:         runtime_profile_has_global(ctx, 'typeof AbortSignal === "function"')
		has_event_target:         runtime_profile_has_global(ctx, 'typeof EventTarget === "function"')
		has_url:                  runtime_profile_has_global(ctx, 'typeof URL === "function"')
		has_buffer:               runtime_profile_has_global(ctx, 'typeof Buffer !== "undefined"')
		has_set_timeout:          runtime_profile_has_global(ctx, 'typeof setTimeout === "function"')
		has_clear_timeout:        runtime_profile_has_global(ctx, 'typeof clearTimeout === "function"')
		has_fetch:                runtime_profile_has_global(ctx, 'typeof fetch === "function"')
		has_process:              runtime_profile_has_global(ctx, 'typeof process === "object"')
		has_node_timers_promises: ctx.has_runtime_module('node:timers/promises')
		has_fs_module:            ctx.has_runtime_module('fs')
		has_path_module:          ctx.has_runtime_module('path')
		has_http_module:          ctx.has_runtime_module('http')
		has_https_module:         ctx.has_runtime_module('https')
		has_os_module:            ctx.has_runtime_module('os')
		has_child_process_module: ctx.has_runtime_module('child_process')
		has_sqlite_module:        ctx.has_runtime_module('sqlite')
		has_mysql_module:         ctx.has_runtime_module('mysql')
	}
}
