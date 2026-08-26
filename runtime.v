module vjsx

import v.vmod

@[typedef]
struct C.JSRuntime {}

@[typedef]
struct C.VJSXInterruptState {}

// Runtime structure based on `JSRuntime` in qjs
// and implemented into `ref`.
pub struct Runtime {
	ref             &C.JSRuntime
	interrupt_state &C.VJSXInterruptState
}

pub const default_runtime_max_stack_size = u32(16 * 1024 * 1024)

// Public vjsx runtime version used by embedded artifact compatibility checks.
const vmod_info = vmod.decode(@VMOD_FILE) or { panic(err) }

pub const version = vmod_info.version

// JSError structure.
@[params]
pub struct JSError {
	Error
pub mut:
	name     string = 'Error'
	stack    string
	message  string
	location string
	expected string
	found    string
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
fn C.vjsx_interrupt_state_new(&C.JSRuntime) &C.VJSXInterruptState
fn C.vjsx_interrupt_state_free(&C.JSRuntime, &C.VJSXInterruptState)
fn C.vjsx_interrupt_set_deadline_after_ms(&C.VJSXInterruptState, u64)
fn C.vjsx_interrupt_clear_deadline(&C.VJSXInterruptState)
fn C.vjsx_interrupt_cancel(&C.VJSXInterruptState)
fn C.vjsx_interrupt_reason(&C.VJSXInterruptState) int

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
	ref := C.JS_NewRuntime()
	interrupt_state := C.vjsx_interrupt_state_new(ref)
	if isnil(interrupt_state) {
		C.JS_FreeRuntime(ref)
		panic('failed to allocate QuickJS interrupt state')
	}
	rt := Runtime{
		ref:             ref
		interrupt_state: interrupt_state
	}
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
	rt.ensure_executable()!
	mut job_ctx := &C.JSContext(unsafe { nil })
	status := C.JS_ExecutePendingJob(rt.ref, &job_ctx)
	if status < 0 {
		if !isnil(job_ctx) {
			return (&Context{
				ref:                job_ctx
				rt:                 rt
				host_cleanup_state: &HostCleanupState{
					cleanups:          []HostCleanup{}
					installed_modules: map[string]bool{}
					bundle_modules:    map[string][]u8{}
					bundle_sources:    map[string]string{}
					bundle_compiled:   map[string][]u8{}
				}
			}).execution_error()
		}
		return error('failed to execute pending QuickJS job')
	}
	return status > 0
}

// Set limit memory. (default to unlimited)
pub fn (rt Runtime) set_memory_limit(limit u32) {
	rt.set_memory_limit_bytes(usize(limit))
}

// Set the memory limit without the legacy u32 size ceiling.
pub fn (rt Runtime) set_memory_limit_bytes(limit usize) {
	C.JS_SetMemoryLimit(rt.ref, limit)
}

// Set maximum stack size in bytes.
pub fn (rt Runtime) set_max_stack_size(stack_size u32) {
	rt.set_max_stack_size_bytes(usize(stack_size))
}

// Set maximum stack size in bytes without the legacy u32 size ceiling.
pub fn (rt Runtime) set_max_stack_size_bytes(stack_size usize) {
	C.JS_SetMaxStackSize(rt.ref, stack_size)
}

// Set gc threshold.
pub fn (rt Runtime) set_gc_threshold(th i64) {
	C.JS_SetGCThreshold(rt.ref, usize(th))
}

// Set the GC threshold using the host's native size type.
pub fn (rt Runtime) set_gc_threshold_bytes(th usize) {
	C.JS_SetGCThreshold(rt.ref, th)
}

// Run qjs garbage collector
pub fn (rt Runtime) run_gc() {
	C.JS_RunGC(rt.ref)
}

// Free runtime.
// Only use this when you are managing ownership manually. When using
// `RuntimeSession`, call `session.close()` instead.
pub fn (rt &Runtime) free() {
	C.vjsx_interrupt_state_free(rt.ref, rt.interrupt_state)
	C.JS_FreeRuntime(rt.ref)
}
