module vjsx

// RuntimeSession owns a Runtime/Context pair so embedders can tear both down
// through one idempotent close path. Prefer this over manual Runtime/Context
// ownership unless you need lower-level control.
pub struct RuntimeSession {
	runtime Runtime
	context &Context
mut:
	closed bool
}

// Create a managed Runtime/Context pair.
// Example:
// ```v
// mut session := vjsx.new_runtime_session()
// defer {
//   session.close()
// }
// ctx := session.context()
// ```
pub fn new_runtime_session(config ContextConfig) RuntimeSession {
	runtime := new_runtime()
	context := runtime.new_context(config)
	return RuntimeSession{
		runtime: runtime
		context: context
	}
}

// Create a managed lightweight script runtime profile.
pub fn new_script_runtime_session(ctx_config ContextConfig, runtime_config ScriptRuntimeConfig) RuntimeSession {
	mut session := new_runtime_session(ctx_config)
	session.context.install_script_runtime(runtime_config)
	return session
}

// Create a managed fuller Node-style runtime profile.
pub fn new_node_runtime_session(ctx_config ContextConfig, runtime_config NodeRuntimeConfig) RuntimeSession {
	mut session := new_runtime_session(ctx_config)
	session.context.install_node_runtime(runtime_config)
	return session
}

// Access the managed context.
pub fn (session RuntimeSession) context() &Context {
	return session.context
}

// Access the managed runtime.
// Most callers should not need this directly.
pub fn (session RuntimeSession) runtime() Runtime {
	return session.runtime
}

// Report whether the session has already been closed.
pub fn (session RuntimeSession) is_closed() bool {
	return session.closed
}

// Close the managed Context and Runtime. Safe to call more than once.
pub fn (mut session RuntimeSession) close() {
	if session.closed {
		return
	}
	session.context.free()
	session.runtime.free()
	session.closed = true
}
