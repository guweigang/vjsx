module vjsx

@[typedef]
struct C.JSRuntime {}

// Runtime structure based on `JSRuntime` in qjs
// and implemented into `ref`.
pub struct Runtime {
	ref &C.JSRuntime
}

pub const default_runtime_max_stack_size = u32(16 * 1024 * 1024)

// JSError structure.
@[params]
pub struct JSError {
	Error
pub mut:
	name    string = 'Error'
	stack   string
	message string
}

// lookup/print JSError message.
pub fn (err &JSError) msg() string {
	return '${err.message}\n${err.stack}'
}

fn C.JS_NewRuntime() &C.JSRuntime
fn C.JS_SetCanBlock(&C.JSRuntime, int)
fn C.JS_FreeRuntime(&C.JSRuntime)
fn C.JS_RunGC(&C.JSRuntime)
fn C.JS_SetMaxStackSize(&C.JSRuntime, usize)
fn C.JS_SetGCThreshold(&C.JSRuntime, usize)
fn C.JS_SetMemoryLimit(&C.JSRuntime, usize)
fn C.JS_IsJobPending(&C.JSRuntime) bool
fn C.JS_ExecutePendingJob(&C.JSRuntime, &&C.JSContext) int

// Create new Runtime.
// This is the low-level manual ownership path. Prefer
// `vjsx.new_runtime_session()` unless you need to manage the Runtime and
// Context separately.
// Example:
// ```v
// rt := vjsx.new_runtime()
// defer {
//   rt.free()
// }
// ```
pub fn new_runtime() Runtime {
	rt := Runtime{C.JS_NewRuntime()}
	C.JS_SetCanBlock(rt.ref, 1)
	return rt
}

// Check if job is pending
pub fn (rt Runtime) is_job_pending() bool {
	return C.JS_IsJobPending(rt.ref)
}

// Execute a single pending QuickJS job if one is ready.
// Returns `true` when a job ran, `false` when the queue was empty.
pub fn (rt Runtime) execute_pending_job() !bool {
	mut job_ctx := &C.JSContext(unsafe { nil })
	status := C.JS_ExecutePendingJob(rt.ref, &job_ctx)
	if status < 0 {
		if !isnil(job_ctx) {
			return (&Context{
				ref:                job_ctx
				rt:                 rt
				host_cleanup_state: &HostCleanupState{}
			}).js_exception()
		}
		return error('failed to execute pending QuickJS job')
	}
	return status > 0
}

// Set limit memory. (default to unlimited)
pub fn (rt Runtime) set_memory_limit(limit u32) {
	C.JS_SetMemoryLimit(rt.ref, usize(limit))
}

// Set maximum stack size in bytes.
pub fn (rt Runtime) set_max_stack_size(stack_size u32) {
	C.JS_SetMaxStackSize(rt.ref, usize(stack_size))
}

// Set gc threshold.
pub fn (rt Runtime) set_gc_threshold(th i64) {
	C.JS_SetGCThreshold(rt.ref, usize(th))
}

// Run qjs garbage collector
pub fn (rt Runtime) run_gc() {
	C.JS_RunGC(rt.ref)
}

// Free runtime.
// Only use this when you are managing ownership manually. When using
// `RuntimeSession`, call `session.close()` instead.
pub fn (rt &Runtime) free() {
	C.JS_FreeRuntime(rt.ref)
}
