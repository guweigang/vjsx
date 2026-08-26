module vjsx

@[typedef]
struct C.JSMemoryUsage {
	malloc_size           i64
	malloc_limit          i64
	memory_used_size      i64
	malloc_count          i64
	memory_used_count     i64
	atom_count            i64
	atom_size             i64
	str_count             i64
	str_size              i64
	obj_count             i64
	obj_size              i64
	prop_count            i64
	prop_size             i64
	shape_count           i64
	shape_size            i64
	js_func_count         i64
	js_func_size          i64
	js_func_code_size     i64
	js_func_pc2line_count i64
	js_func_pc2line_size  i64
	c_func_count          i64
	array_count           i64
	fast_array_count      i64
	fast_array_elements   i64
	binary_object_count   i64
	binary_object_size    i64
}

fn C.JS_ComputeMemoryUsage(&C.JSRuntime, &C.JSMemoryUsage)

// RuntimeMemoryUsage is a stable, host-facing subset of QuickJS memory data.
pub struct RuntimeMemoryUsage {
pub:
	malloc_size        i64
	malloc_limit       i64
	memory_used_size   i64
	malloc_count       i64
	memory_used_count  i64
	atom_count         i64
	atom_size          i64
	string_count       i64
	string_size        i64
	object_count       i64
	object_size        i64
	property_count     i64
	property_size      i64
	shape_count        i64
	shape_size         i64
	js_function_count  i64
	js_function_size   i64
	js_code_size       i64
	array_count        i64
	fast_array_count   i64
	binary_object_size i64
}

pub fn (rt Runtime) memory_usage() RuntimeMemoryUsage {
	mut raw := C.JSMemoryUsage{}
	C.JS_ComputeMemoryUsage(rt.ref, &raw)
	return RuntimeMemoryUsage{
		malloc_size:        raw.malloc_size
		malloc_limit:       raw.malloc_limit
		memory_used_size:   raw.memory_used_size
		malloc_count:       raw.malloc_count
		memory_used_count:  raw.memory_used_count
		atom_count:         raw.atom_count
		atom_size:          raw.atom_size
		string_count:       raw.str_count
		string_size:        raw.str_size
		object_count:       raw.obj_count
		object_size:        raw.obj_size
		property_count:     raw.prop_count
		property_size:      raw.prop_size
		shape_count:        raw.shape_count
		shape_size:         raw.shape_size
		js_function_count:  raw.js_func_count
		js_function_size:   raw.js_func_size
		js_code_size:       raw.js_func_code_size
		array_count:        raw.array_count
		fast_array_count:   raw.fast_array_count
		binary_object_size: raw.binary_object_size
	}
}

pub fn (session RuntimeSession) memory_usage() RuntimeMemoryUsage {
	if session.closed {
		return RuntimeMemoryUsage{}
	}
	return session.runtime.memory_usage()
}
