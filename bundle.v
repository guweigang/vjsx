module vjsx

import crypto.sha256
import json2

const bundle_magic = [u8(`V`), `J`, `S`, `X`, `B`, `N`, `D`, 0]
const bundle_format_version = u16(1)
const bundle_fixed_header_size = 60
const bundle_module_prefix = 'vjsx-bundle/'

fn C.vjsx_js_value_is_module(JSValueConst) int
fn C.vjsx_js_get_module_def_namespace_out(&C.JSContext, &C.JSModuleDef, &C.JSValue)
fn C.vjsx_js_throw_bundle_module_not_found(&C.JSContext, &char)

// BundleSourceModule is an emitted ES module ready for QuickJS compilation.
// Names must use the stable `vjsx-bundle/<app>/...` namespace.
pub struct BundleSourceModule {
pub:
	name   string
	source string
}

// CompileBundleOptions describes a complete static module graph artifact.
@[params]
pub struct CompileBundleOptions {
pub:
	app_name        string = 'app'
	entry           string @[required]
	runtime_profile string = 'node'
	strip_source    bool
	strip_debug     bool
}

struct BundleManifestModule {
pub:
	name   string
	offset u64
	length u64
}

struct BundleManifest {
pub:
	format_version  int
	vjsx_version    string
	quickjs_abi     string
	runtime_profile string
	app_name        string
	entry           string
	modules         []BundleManifestModule
}

struct ParsedBundle {
	manifest BundleManifest
	modules  map[string][]u8
}

// BundleInfo is safe metadata returned without loading QuickJS bytecode.
pub struct BundleInfo {
pub:
	app_name        string
	entry           string
	runtime_profile string
	module_count    int
	format_version  int
	vjsx_version    string
	quickjs_abi     string
}

fn is_bundle_module_name(name string) bool {
	return name.starts_with(bundle_module_prefix)
}

fn validate_bundle_module_name(name string) ! {
	if !is_bundle_module_name(name) || name.contains('\\') || name.contains('/../')
		|| name.ends_with('/..') {
		return error('invalid vjsx bundle module name: ${name}')
	}
}

fn bundle_checksum(manifest []u8, payload []u8) []u8 {
	mut input := []u8{cap: manifest.len + payload.len}
	input << manifest
	input << payload
	return sha256.sum256(input)
}

fn compile_es_module_payload(ctx &Context, source BundleSourceModule, options CompileBundleOptions) ![]u8 {
	mut compiled_ref := ctx.js_undefined().ref
	C.vjsx_js_eval_out(ctx.ref, source.source.str, usize(source.source.len), source.name.str,
		type_module | type_compile_only, &compiled_ref)
	compiled := ctx.c_val(compiled_ref)
	defer {
		compiled.free()
	}
	if compiled.is_exception() {
		return ctx.execution_error()
	}
	if C.vjsx_js_value_is_module(compiled.ref) == 0 {
		return error('QuickJS did not compile an ES module: ${source.name}')
	}
	mut payload_len := usize(0)
	payload_ptr := C.vjsx_js_write_bytecode(ctx.ref, &payload_len, compiled.ref,
		int(options.strip_source), int(options.strip_debug))
	if isnil(payload_ptr) {
		return ctx.execution_error()
	}
	defer {
		C.js_free(ctx.ref, payload_ptr)
	}
	mut payload := []u8{len: int(payload_len)}
	unsafe {
		vmemcpy(payload.data, payload_ptr, payload_len)
	}
	return payload
}

fn (ctx &Context) begin_bundle_compilation(modules []BundleSourceModule, options CompileBundleOptions) {
	mut state := ctx.host_cleanup_state
	state.bundle_sources = map[string]string{}
	state.bundle_compiled = map[string][]u8{}
	for source in modules {
		state.bundle_sources[source.name] = source.source
	}
	state.bundle_strip_src = options.strip_source
	state.bundle_strip_dbg = options.strip_debug
	state.bundle_compiling = true
}

fn (ctx &Context) end_bundle_compilation() {
	mut state := ctx.host_cleanup_state
	state.bundle_sources = map[string]string{}
	state.bundle_compiling = false
	state.bundle_strip_src = false
	state.bundle_strip_dbg = false
}

fn (ctx &Context) bundle_compile_source(name string) ?string {
	state := ctx.host_cleanup_state
	if !state.bundle_compiling || name !in state.bundle_sources {
		return none
	}
	return state.bundle_sources[name]
}

fn (ctx &Context) bundle_compiled_bytecode(name string) ?[]u8 {
	state := ctx.host_cleanup_state
	if name !in state.bundle_compiled {
		return none
	}
	return state.bundle_compiled[name]
}

fn (ctx &Context) store_bundle_compiled_bytecode(name string, bytecode []u8) {
	mut state := ctx.host_cleanup_state
	state.bundle_compiled[name] = bytecode
}

fn (ctx &Context) compile_bundle_loader_module(c_ctx &C.JSContext, name string, source string) !&C.JSModuleDef {
	mut ref := C.JSValue{}
	C.vjsx_js_eval_out(c_ctx, source.str, usize(source.len), name.str,
		type_module | type_compile_only, &ref)
	if C.JS_IsException(ref) == 1 {
		return error('failed to compile bundle dependency: ${name}')
	}
	if C.vjsx_js_value_is_module(ref) == 0 {
		C.JS_FreeValue(c_ctx, ref)
		return error('bundle dependency is not an ES module: ${name}')
	}
	mut payload_len := usize(0)
	state := ctx.host_cleanup_state
	payload_ptr := C.vjsx_js_write_bytecode(c_ctx, &payload_len, ref, int(state.bundle_strip_src),
		int(state.bundle_strip_dbg))
	if isnil(payload_ptr) {
		C.JS_FreeValue(c_ctx, ref)
		return error('failed to serialize bundle dependency: ${name}')
	}
	mut payload := []u8{len: int(payload_len)}
	unsafe {
		vmemcpy(payload.data, payload_ptr, payload_len)
	}
	C.js_free(c_ctx, payload_ptr)
	ctx.store_bundle_compiled_bytecode(name, payload)
	C.js_module_set_import_meta(c_ctx, ref, false, false)
	module_def := C.vjsx_js_value_to_module_def(ref)
	C.JS_FreeValue(c_ctx, ref)
	return module_def
}

// Compile a complete emitted ES module graph into a `.vjsx` bundle.
pub fn (ctx &Context) compile_bundle(modules []BundleSourceModule, options CompileBundleOptions) ![]u8 {
	ctx.rt.ensure_executable()!
	bytecode_profile_id(options.runtime_profile)!
	if modules.len == 0 {
		return error('vjsx bundle requires at least one module')
	}
	validate_bundle_module_name(options.entry)!
	mut sorted_modules := modules.clone()
	sorted_modules.sort(a.name < b.name)
	mut seen := map[string]bool{}
	mut has_entry := false
	for source in sorted_modules {
		validate_bundle_module_name(source.name)!
		if source.name in seen {
			return error('duplicate vjsx bundle module: ${source.name}')
		}
		seen[source.name] = true
		if source.name == options.entry {
			has_entry = true
		}
	}
	if !has_entry {
		return error('vjsx bundle entry is not present in module graph: ${options.entry}')
	}
	ctx.begin_bundle_compilation(sorted_modules, options)
	defer {
		ctx.end_bundle_compilation()
	}
	entry_source := sorted_modules.filter(it.name == options.entry)[0]
	entry_payload := compile_es_module_payload(ctx, entry_source, options)!
	ctx.store_bundle_compiled_bytecode(options.entry, entry_payload)
	for source in sorted_modules {
		if _ := ctx.bundle_compiled_bytecode(source.name) {
			continue
		}
		module_payload := compile_es_module_payload(ctx, source, options)!
		ctx.store_bundle_compiled_bytecode(source.name, module_payload)
	}
	mut manifest_modules := []BundleManifestModule{cap: sorted_modules.len}
	mut payload := []u8{}
	for source in sorted_modules {
		module_payload := ctx.bundle_compiled_bytecode(source.name) or {
			return error('bundle module was not compiled: ${source.name}')
		}
		manifest_modules << BundleManifestModule{
			name:   source.name
			offset: u64(payload.len)
			length: u64(module_payload.len)
		}
		payload << module_payload
	}
	manifest := BundleManifest{
		format_version:  int(bundle_format_version)
		vjsx_version:    version
		quickjs_abi:     quickjs_abi_fingerprint()
		runtime_profile: options.runtime_profile
		app_name:        options.app_name
		entry:           options.entry
		modules:         manifest_modules
	}
	manifest_bytes := json2.encode(manifest, escape_unicode: true).bytes()
	mut out := []u8{cap: bundle_fixed_header_size + manifest_bytes.len + payload.len}
	out << bundle_magic
	append_u16_le(mut out, bundle_format_version)
	append_u16_le(mut out, 0)
	append_u64_le(mut out, u64(manifest_bytes.len))
	append_u64_le(mut out, u64(payload.len))
	out << bundle_checksum(manifest_bytes, payload)
	out << manifest_bytes
	out << payload
	return out
}

fn parse_bundle(data []u8) !ParsedBundle {
	if data.len < bundle_fixed_header_size {
		return error('invalid vjsx bundle: truncated header')
	}
	if data[..bundle_magic.len] != bundle_magic {
		return error('invalid vjsx bundle: bad magic')
	}
	format_version := read_u16_le(data, 8)!
	if format_version != bundle_format_version {
		return error('incompatible vjsx bundle format: artifact=${format_version}, runtime=${bundle_format_version}')
	}
	manifest_len_u64 := read_u64_le(data, 12)!
	payload_len_u64 := read_u64_le(data, 20)!
	if manifest_len_u64 > u64(data.len) || payload_len_u64 > u64(data.len) {
		return error('invalid vjsx bundle: declared section is too large')
	}
	manifest_len := int(manifest_len_u64)
	payload_len := int(payload_len_u64)
	if bundle_fixed_header_size + manifest_len + payload_len != data.len {
		return error('invalid vjsx bundle: inconsistent lengths')
	}
	manifest_bytes := data[bundle_fixed_header_size..bundle_fixed_header_size + manifest_len]
	payload := data[bundle_fixed_header_size + manifest_len..]
	if bundle_checksum(manifest_bytes, payload) != data[28..60] {
		return error('invalid vjsx bundle: checksum mismatch')
	}
	manifest := json2.decode[BundleManifest](manifest_bytes.bytestr()) or {
		return error('invalid vjsx bundle manifest: ${err.msg()}')
	}
	if manifest.format_version != int(bundle_format_version) {
		return error('incompatible vjsx bundle manifest format: artifact=${manifest.format_version}, runtime=${bundle_format_version}')
	}
	if manifest.modules.len == 0 {
		return error('invalid vjsx bundle: empty module graph')
	}
	validate_bundle_module_name(manifest.entry)!
	mut modules := map[string][]u8{}
	mut expected_offset := u64(0)
	mut has_entry := false
	for item in manifest.modules {
		validate_bundle_module_name(item.name)!
		if item.name in modules {
			return error('invalid vjsx bundle: duplicate module ${item.name}')
		}
		if item.offset != expected_offset || item.length == 0 || item.offset > u64(payload.len)
			|| item.length > u64(payload.len) - item.offset {
			return error('invalid vjsx bundle module range: ${item.name}')
		}
		start := int(item.offset)
		end := int(item.offset + item.length)
		modules[item.name] = payload[start..end].clone()
		expected_offset += item.length
		if item.name == manifest.entry {
			has_entry = true
		}
	}
	if expected_offset != u64(payload.len) || !has_entry {
		return error('invalid vjsx bundle: incomplete module graph')
	}
	return ParsedBundle{
		manifest: manifest
		modules:  modules
	}
}

// Inspect a `.vjsx` bundle without registering or evaluating its modules.
pub fn bundle_info(data []u8) !BundleInfo {
	parsed := parse_bundle(data)!
	return BundleInfo{
		app_name:        parsed.manifest.app_name
		entry:           parsed.manifest.entry
		runtime_profile: parsed.manifest.runtime_profile
		module_count:    parsed.manifest.modules.len
		format_version:  parsed.manifest.format_version
		vjsx_version:    parsed.manifest.vjsx_version
		quickjs_abi:     parsed.manifest.quickjs_abi
	}
}

fn (ctx &Context) bundle_module_bytecode(name string) ?[]u8 {
	state := ctx.host_cleanup_state
	if name !in state.bundle_modules {
		return none
	}
	return state.bundle_modules[name]
}

fn (ctx &Context) register_bundle_modules(modules map[string][]u8) {
	mut state := ctx.host_cleanup_state
	for name, bytecode in modules {
		state.bundle_modules[name] = bytecode
	}
}

fn (ctx &Context) validate_bundle_manifest(manifest BundleManifest) ! {
	current_abi := quickjs_abi_fingerprint()
	if manifest.quickjs_abi != current_abi {
		return error('incompatible QuickJS ABI: artifact=${manifest.quickjs_abi}, runtime=${current_abi}')
	}
	if manifest.vjsx_version != version {
		return error('incompatible vjsx runtime: artifact=${manifest.vjsx_version}, runtime=${version}')
	}
	if manifest.runtime_profile != ctx.runtime_profile() {
		return error('incompatible runtime profile: artifact=${manifest.runtime_profile}, context=${ctx.runtime_profile()}')
	}
}

// Register, link and evaluate a trusted `.vjsx` bundle entirely from memory.
// The returned ScriptModule retains the entry module namespace for reuse.
pub fn (ctx &Context) load_bundle(data []u8) !ScriptModule {
	ctx.rt.ensure_executable()!
	parsed := parse_bundle(data)!
	ctx.validate_bundle_manifest(parsed.manifest)!
	ctx.register_bundle_modules(parsed.modules)
	entry_bytecode := parsed.modules[parsed.manifest.entry]
	mut entry_ref := ctx.js_undefined().ref
	C.vjsx_js_read_bytecode_out(ctx.ref, &entry_bytecode[0], usize(entry_bytecode.len), &entry_ref)
	entry := ctx.c_val(entry_ref)
	if entry.is_exception() {
		return ctx.execution_error()
	}
	if C.vjsx_js_value_is_module(entry.ref) == 0 {
		entry.free()
		return error('invalid vjsx bundle entry bytecode: ${parsed.manifest.entry}')
	}
	if C.vjsx_js_resolve_module(ctx.ref, entry.ref) < 0 {
		entry.free()
		return ctx.execution_error()
	}
	// JS_EvalFunction consumes entry.ref, so retain the registry-owned module
	// definition pointer for obtaining its namespace after initialization.
	entry_module_def := C.vjsx_js_value_to_module_def(entry.ref)
	def_set_meta(ctx, entry.ref)
	mut result_ref := ctx.js_undefined().ref
	C.vjsx_js_eval_function_out(ctx.ref, entry.ref, &result_ref)
	mut awaited_ref := ctx.js_undefined().ref
	C.vjsx_js_std_await_out(ctx.ref, result_ref, &awaited_ref)
	awaited := ctx.c_val(awaited_ref)
	if awaited.is_exception() {
		return ctx.execution_error()
	}
	awaited.free()
	mut namespace_ref := ctx.js_undefined().ref
	C.vjsx_js_get_module_def_namespace_out(ctx.ref, entry_module_def, &namespace_ref)
	namespace := ctx.c_val(namespace_ref)
	if namespace.is_exception() {
		return ctx.execution_error()
	}
	return ScriptModule{
		ctx:     unsafe { ctx }
		exports: namespace
		state:   &ScriptModuleState{}
	}
}

// Alias for load_bundle(), emphasizing entry-module evaluation.
pub fn (ctx &Context) eval_bundle(data []u8) !ScriptModule {
	return ctx.load_bundle(data)
}
