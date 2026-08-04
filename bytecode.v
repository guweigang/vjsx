module vjsx

import crypto.sha256
import os

const bytecode_magic = [u8(`V`), `J`, `S`, `X`, `Q`, `B`, `C`, 0]
const bytecode_format_version = u16(1)
const bytecode_fixed_header_size = 64
const bytecode_kind_commonjs = u8(1)
const bytecode_profile_node = u8(1)
const bytecode_profile_script = u8(2)
const bytecode_profile_browser = u8(3)

fn C.vjsx_js_write_bytecode(&C.JSContext, &usize, JSValueConst, int, int) &u8
fn C.vjsx_js_read_bytecode_out(&C.JSContext, &u8, usize, &C.JSValue)
fn C.vjsx_quickjs_version() &char

// CompileModuleOptions describes a self-contained CommonJS/UMD compilation
// unit. Entry-only bytecode deliberately has no source module resolver.
@[params]
pub struct CompileModuleOptions {
pub:
	filename        string = '<module>'
	runtime_profile string = 'node'
	strip_source    bool
	strip_debug     bool
}

struct BytecodeArtifact {
	profile  string
	qjs_abi  string
	vjsx     string
	filename string
	payload  []u8
}

fn bytecode_profile_id(profile string) !u8 {
	return match profile {
		'node' { bytecode_profile_node }
		'script' { bytecode_profile_script }
		'browser' { bytecode_profile_browser }
		else { return error('unsupported bytecode runtime profile: ${profile}') }
	}
}

fn bytecode_profile_name(profile u8) !string {
	return match profile {
		bytecode_profile_node { 'node' }
		bytecode_profile_script { 'script' }
		bytecode_profile_browser { 'browser' }
		else { return error('unsupported bytecode runtime profile id: ${profile}') }
	}
}

fn quickjs_abi_fingerprint() string {
	qjs_version := unsafe { cstring_to_vstring(C.vjsx_quickjs_version()) }
	backend := $if quickjs_legacy ? { 'quickjs' } $else { 'quickjs-ng' }
	endian := $if little_endian { 'le' } $else { 'be' }
	return '${backend}/${qjs_version}/ptr${sizeof(voidptr) * 8}/${endian}/bignum'
}

fn append_u16_le(mut out []u8, value u16) {
	out << u8(value)
	out << u8(value >> 8)
}

fn append_u64_le(mut out []u8, value u64) {
	for shift in 0 .. 8 {
		out << u8(value >> (shift * 8))
	}
}

fn read_u16_le(data []u8, offset int) !u16 {
	if offset < 0 || offset + 2 > data.len {
		return error('truncated vjsx bytecode header')
	}
	return u16(data[offset]) | (u16(data[offset + 1]) << 8)
}

fn read_u64_le(data []u8, offset int) !u64 {
	if offset < 0 || offset + 8 > data.len {
		return error('truncated vjsx bytecode header')
	}
	mut value := u64(0)
	for shift in 0 .. 8 {
		value |= u64(data[offset + shift]) << (shift * 8)
	}
	return value
}

fn bytecode_checksum(payload []u8) []u8 {
	return sha256.sum256(payload)
}

fn wrap_bytecode_artifact(payload []u8, options CompileModuleOptions) ![]u8 {
	profile := bytecode_profile_id(options.runtime_profile)!
	qjs_abi := quickjs_abi_fingerprint()
	qjs_bytes := qjs_abi.bytes()
	vjsx_bytes := version.bytes()
	filename_bytes := options.filename.bytes()
	if qjs_bytes.len > 65535 || vjsx_bytes.len > 65535 || filename_bytes.len > 65535 {
		return error('vjsx bytecode metadata is too large')
	}
	header_size := bytecode_fixed_header_size + qjs_bytes.len + vjsx_bytes.len + filename_bytes.len
	if header_size > 65535 {
		return error('vjsx bytecode header is too large')
	}
	mut out := []u8{cap: header_size + payload.len}
	out << bytecode_magic
	append_u16_le(mut out, bytecode_format_version)
	append_u16_le(mut out, u16(header_size))
	out << profile
	out << bytecode_kind_commonjs
	mut flags := u16(0)
	if options.strip_source {
		flags |= 1
	}
	if options.strip_debug {
		flags |= 2
	}
	append_u16_le(mut out, flags)
	append_u16_le(mut out, u16(qjs_bytes.len))
	append_u16_le(mut out, u16(vjsx_bytes.len))
	append_u16_le(mut out, u16(filename_bytes.len))
	append_u16_le(mut out, 0)
	append_u64_le(mut out, u64(payload.len))
	out << bytecode_checksum(payload)
	out << qjs_bytes
	out << vjsx_bytes
	out << filename_bytes
	out << payload
	return out
}

fn parse_bytecode_artifact(data []u8) !BytecodeArtifact {
	if data.len < bytecode_fixed_header_size {
		return error('invalid vjsx bytecode: truncated header')
	}
	if data[..bytecode_magic.len] != bytecode_magic {
		return error('invalid vjsx bytecode: bad magic')
	}
	format_version := read_u16_le(data, 8)!
	if format_version != bytecode_format_version {
		return error('incompatible vjsx bytecode format: artifact=${format_version}, runtime=${bytecode_format_version}')
	}
	header_size := int(read_u16_le(data, 10)!)
	if header_size < bytecode_fixed_header_size || header_size > data.len {
		return error('invalid vjsx bytecode: bad header size')
	}
	if data[13] != bytecode_kind_commonjs {
		return error('unsupported vjsx bytecode kind: ${data[13]}')
	}
	profile := bytecode_profile_name(data[12])!
	qjs_len := int(read_u16_le(data, 16)!)
	vjsx_len := int(read_u16_le(data, 18)!)
	filename_len := int(read_u16_le(data, 20)!)
	payload_len_u64 := read_u64_le(data, 24)!
	if payload_len_u64 > u64(data.len) {
		return error('invalid vjsx bytecode: payload is too large')
	}
	payload_len := int(payload_len_u64)
	metadata_end := bytecode_fixed_header_size + qjs_len + vjsx_len + filename_len
	if metadata_end != header_size || header_size + payload_len != data.len {
		return error('invalid vjsx bytecode: inconsistent lengths')
	}
	mut offset := bytecode_fixed_header_size
	qjs_abi := data[offset..offset + qjs_len].bytestr()
	offset += qjs_len
	vjsx_version := data[offset..offset + vjsx_len].bytestr()
	offset += vjsx_len
	filename := data[offset..offset + filename_len].bytestr()
	payload := data[header_size..].clone()
	expected_checksum := data[32..64]
	if bytecode_checksum(payload) != expected_checksum {
		return error('invalid vjsx bytecode: checksum mismatch')
	}
	return BytecodeArtifact{
		profile:  profile
		qjs_abi:  qjs_abi
		vjsx:     vjsx_version
		filename: filename
		payload:  payload
	}
}

fn commonjs_factory_source(source string) string {
	return '(function (module, exports, require, __filename, __dirname) {\n${source}\n; return module.exports;\n})'
}

// Compile a self-contained UMD/CommonJS source string into a versioned vjsx
// bytecode artifact. The JavaScript body is compiled but never evaluated.
pub fn compile_module(source string, options CompileModuleOptions) ![]u8 {
	bytecode_profile_id(options.runtime_profile)!
	mut session := new_runtime_session()
	defer {
		session.close()
	}
	return session.context().compile_module_bytecode(source, options)
}

// Compile a self-contained UMD/CommonJS source string using an existing
// context. This is the lower-level counterpart of compile_module().
pub fn (ctx &Context) compile_module_bytecode(source string, options CompileModuleOptions) ![]u8 {
	ctx.rt.ensure_executable()!
	factory_source := commonjs_factory_source(source)
	mut compiled_ref := ctx.js_undefined().ref
	C.vjsx_js_eval_out(ctx.ref, factory_source.str, usize(factory_source.len),
		options.filename.str, type_global | type_compile_only, &compiled_ref)
	compiled := ctx.c_val(compiled_ref)
	defer {
		compiled.free()
	}
	if compiled.is_exception() {
		return ctx.execution_error()
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
	return wrap_bytecode_artifact(payload, options)
}

fn (ctx &Context) validate_bytecode_artifact(artifact BytecodeArtifact) ! {
	current_abi := quickjs_abi_fingerprint()
	if artifact.qjs_abi != current_abi {
		return error('incompatible QuickJS ABI: artifact=${artifact.qjs_abi}, runtime=${current_abi}')
	}
	if artifact.vjsx != version {
		return error('incompatible vjsx runtime: artifact=${artifact.vjsx}, runtime=${version}')
	}
	if artifact.profile != ctx.runtime_profile() {
		return error('incompatible runtime profile: artifact=${artifact.profile}, context=${ctx.runtime_profile()}')
	}
}

// Load, evaluate and initialize a trusted vjsx CommonJS bytecode artifact.
// The returned handle owns module.exports and can be retained for repeated
// calls without reloading or reinitializing the bytecode.
pub fn (ctx &Context) load_bytecode(bytecode []u8) !ScriptModule {
	ctx.rt.ensure_executable()!
	artifact := parse_bytecode_artifact(bytecode)!
	ctx.validate_bytecode_artifact(artifact)!
	if artifact.payload.len == 0 {
		return error('invalid vjsx bytecode: empty payload')
	}
	mut compiled_ref := ctx.js_undefined().ref
	payload_ptr := &artifact.payload[0]
	C.vjsx_js_read_bytecode_out(ctx.ref, payload_ptr, usize(artifact.payload.len), &compiled_ref)
	compiled := ctx.c_val(compiled_ref)
	if compiled.is_exception() {
		return ctx.execution_error()
	}
	// JS_EvalFunction consumes the compiled bytecode object.
	mut factory_ref := ctx.js_undefined().ref
	C.vjsx_js_eval_function_out(ctx.ref, compiled.ref, &factory_ref)
	factory := ctx.c_val(factory_ref)
	if factory.is_exception() {
		return ctx.execution_error()
	}
	defer {
		factory.free()
	}
	if !factory.is_function() {
		return error('invalid vjsx bytecode: CommonJS factory was not produced')
	}
	module_object := ctx.js_object()
	defer {
		module_object.free()
	}
	exports_object := ctx.js_object()
	defer {
		exports_object.free()
	}
	module_object.set('exports', exports_object)
	undefined_value := ctx.js_undefined()
	filename := if artifact.filename == '' { '<bytecode>' } else { artifact.filename }
	dirname := if filename == '<module>' || filename == '<bytecode>' {
		'.'
	} else {
		os.dir(filename)
	}
	filename_value := ctx.js_string(filename)
	defer {
		filename_value.free()
	}
	dirname_value := ctx.js_string(dirname)
	defer {
		dirname_value.free()
	}
	result := ctx.call_this(exports_object, factory, module_object, exports_object,
		undefined_value, filename_value, dirname_value)!
	result.free()
	exports := module_object.get('exports')
	if exports.is_undefined() {
		exports.free()
		return error('invalid CommonJS bytecode: module.exports is undefined')
	}
	return ScriptModule{
		ctx:     unsafe { ctx }
		exports: exports
		state:   &ScriptModuleState{}
	}
}

// Alias for load_bytecode(), emphasizing that loading initializes the
// CommonJS module once and returns its exports.
pub fn (ctx &Context) eval_bytecode(bytecode []u8) !ScriptModule {
	return ctx.load_bytecode(bytecode)
}
