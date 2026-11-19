module vjsx

import sync

// DynamicImportRequest describes one JavaScript import() request. The loader
// runs on the owning lane but may hand its completion port to a worker.
pub struct DynamicImportRequest {
pub:
	id        u64
	base_name string
	specifier string
}

pub type DynamicImportLoaderFn = fn (DynamicImportRequest, DynamicImportCompletionPort)

struct DynamicImportRecord {
	id         u64
	base_name  string
	specifier  string
	token      Value
	attributes Value
}

struct DynamicImportCompletion {
	id      u64
	source  string
	message string
	reject  bool
}

struct DynamicImportState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	loader     ?DynamicImportLoaderFn
	next_id    u64 = 1
	records    map[u64]DynamicImportRecord
	queued     []DynamicImportCompletion
	sources    map[string]string
	closed     bool
	session_id string
	ready_fn   RuntimeHostAsyncReadyFn = runtime_host_async_default_ready
}

fn new_dynamic_import_state() &DynamicImportState {
	return &DynamicImportState{
		records: map[u64]DynamicImportRecord{}
		sources: map[string]string{}
	}
}

// DynamicImportCompletionPort contains no QuickJS values and is safe to move
// to worker threads. Completion is delivered later on the owning lane.
pub struct DynamicImportCompletionPort {
	id    u64
	state &DynamicImportState
}

fn (port DynamicImportCompletionPort) submit(completion DynamicImportCompletion) bool {
	mut state := port.state
	state.guard.lock()
	if state.closed || port.id !in state.records {
		state.guard.unlock()
		return false
	}
	for queued in state.queued {
		if queued.id == port.id {
			state.guard.unlock()
			return false
		}
	}
	state.queued << completion
	ready_fn := state.ready_fn
	session_id := state.session_id
	state.guard.unlock()
	ready_fn(RuntimeHostAsyncReadyRequest{
		session_id:   session_id
		operation_id: port.id
	})
	return true
}

// Resolve the import with JavaScript module source text.
pub fn (port DynamicImportCompletionPort) resolve_source(source string) bool {
	return port.submit(DynamicImportCompletion{
		id:     port.id
		source: source
	})
}

// Reject the import with a host-provided diagnostic.
pub fn (port DynamicImportCompletionPort) reject(message string) bool {
	return port.submit(DynamicImportCompletion{
		id:      port.id
		message: if message == '' { 'dynamic import failed' } else { message }
		reject:  true
	})
}

type VJSXDynamicImportFunc = fn (&C.JSContext, &char, &char, C.JSValue, JSValueConst, voidptr)

fn C.vjsx_set_dynamic_import_func(&C.JSRuntime, &VJSXDynamicImportFunc, voidptr) int

fn C.vjsx_js_load_module_out(&C.JSContext, &char, &char, JSValueConst, &C.JSValue)

fn C.vjsx_js_finish_dynamic_import(&C.JSContext, C.JSValue, C.JSValue) int

fn C.vjsx_js_reject_dynamic_import(&C.JSContext, C.JSValue, &char) int

fn vjsx_dynamic_import_callback(c_ctx &C.JSContext, basename &char, filename &char, token C.JSValue, attributes JSValueConst, _opaque voidptr) {
	ctx := context_from_c_ctx(c_ctx)
	if isnil(ctx) {
		C.vjsx_js_reject_dynamic_import(c_ctx, token, c'vjsx context is unavailable')
		return
	}
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	if state.closed {
		state.guard.unlock()
		C.vjsx_js_reject_dynamic_import(c_ctx, token, c'vjsx context is closed')
		return
	}
	loader := state.loader or {
		state.guard.unlock()
		C.vjsx_js_reject_dynamic_import(c_ctx, token, c'dynamic import loader is not installed')
		return
	}
	id := state.next_id
	state.next_id++
	base_name := if isnil(basename) { '' } else { v_str(basename) }
	specifier := if isnil(filename) { '' } else { v_str(filename) }
	state.records[id] = DynamicImportRecord{
		id:         id
		base_name:  base_name
		specifier:  specifier
		token:      ctx.c_val(token)
		attributes: ctx.c_val(attributes).dup_value()
	}
	state.guard.unlock()
	loader(DynamicImportRequest{
		id:        id
		base_name: base_name
		specifier: specifier
	}, DynamicImportCompletionPort{
		id:    id
		state: state
	})
}

// Install an opt-in asynchronous source loader for JavaScript import().
// Static imports and the existing synchronous module loader are unchanged.
pub fn (ctx &Context) install_dynamic_import_loader(loader DynamicImportLoaderFn) ! {
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	if state.closed {
		state.guard.unlock()
		return error('dynamic import state is closed')
	}
	state.loader = loader
	state.guard.unlock()
	if C.vjsx_set_dynamic_import_func(ctx.rt.ref, &vjsx_dynamic_import_callback, C.NULL) == 0 {
		return error('asynchronous dynamic import requires quickjs-ng 0.18.0 or newer')
	}
}

fn (ctx &Context) take_dynamic_import_source(name string) ?string {
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	if name !in state.sources {
		state.guard.unlock()
		return none
	}
	source := state.sources[name]
	state.sources.delete(name)
	state.guard.unlock()
	return source
}

fn (ctx &Context) settle_dynamic_import(record DynamicImportRecord, completion DynamicImportCompletion) ! {
	defer {
		record.attributes.free()
	}
	if completion.reject {
		if C.vjsx_js_reject_dynamic_import(ctx.ref, record.token.ref, completion.message.str) < 0 {
			return error('failed to reject dynamic import: ${record.specifier}')
		}
		return
	}
	module_name := normalize_runtime_module_specifier(record.base_name, record.specifier) or {
		C.vjsx_js_reject_dynamic_import(ctx.ref, record.token.ref, err.msg().str)
		return err
	}
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	state.sources[module_name] = completion.source
	state.guard.unlock()
	mut module_promise := C.JSValue{}
	C.vjsx_js_load_module_out(ctx.ref, record.base_name.str, record.specifier.str,
		record.attributes.ref, &module_promise)
	state.guard.lock()
	state.sources.delete(module_name)
	state.guard.unlock()
	if C.vjsx_js_finish_dynamic_import(ctx.ref, record.token.ref, module_promise) < 0 {
		return error('failed to finish dynamic import: ${record.specifier}')
	}
}

// Settle completed dynamic imports on the Context's owning lane.
pub fn (mut session RuntimeSession) drain_dynamic_import_events() !int {
	if session.is_closed() {
		return 0
	}
	return session.context.drain_context_dynamic_import_events()
}

fn (ctx &Context) drain_context_dynamic_import_events() !int {
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	events := state.queued.clone()
	state.queued = []DynamicImportCompletion{}
	state.guard.unlock()
	mut settled := 0
	for event in events {
		state.guard.lock()
		record := state.records[event.id] or {
			state.guard.unlock()
			continue
		}
		state.records.delete(event.id)
		state.guard.unlock()
		ctx.settle_dynamic_import(record, event)!
		settled++
	}
	return settled
}

fn (ctx &Context) configure_dynamic_import_ready(session_id string, ready_fn RuntimeHostAsyncReadyFn) {
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	state.session_id = session_id
	state.ready_fn = ready_fn
	state.guard.unlock()
}

pub fn (session RuntimeSession) pending_dynamic_import_count() int {
	mut state := session.context.host_cleanup_state.dynamic_import
	state.guard.lock()
	count := state.records.len
	state.guard.unlock()
	return count
}

pub fn (session RuntimeSession) pending_dynamic_import_event_count() int {
	mut state := session.context.host_cleanup_state.dynamic_import
	state.guard.lock()
	count := state.queued.len
	state.guard.unlock()
	return count
}

fn (ctx &Context) close_dynamic_imports() {
	mut state := ctx.host_cleanup_state.dynamic_import
	state.guard.lock()
	if state.closed {
		state.guard.unlock()
		return
	}
	state.closed = true
	records := state.records.values()
	state.records = map[u64]DynamicImportRecord{}
	state.queued = []DynamicImportCompletion{}
	state.sources = map[string]string{}
	state.guard.unlock()
	for record in records {
		C.vjsx_js_reject_dynamic_import(ctx.ref, record.token.ref, c'vjsx context closed')
		record.attributes.free()
	}
}
