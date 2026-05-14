#ifndef VJSX_QUICKJS_COMPAT_H
#define VJSX_QUICKJS_COMPAT_H

#include "quickjs.h"

#if defined(VJSX_QUICKJS_NG)
#define JS_IsArray(ctx, val) JS_IsArray(val)
#define JS_IsError(ctx, val) JS_IsError(val)
#define JS_StrictEq(ctx, op1, op2) JS_IsStrictEqual(ctx, op1, op2)
#endif

/*
 * Some QuickJS builds expose BigFloat/BigDecimal initialization helpers,
 * while others do not. Keep the default path portable by making this a
 * no-op unless we explicitly opt into those intrinsics for a compatible
 * QuickJS checkout.
 */
#if defined(VJS_ENABLE_BIGNUM_INTRINSICS)
static inline void vjsx_js_add_bignum_intrinsics(JSContext *ctx) {
	JS_AddIntrinsicBigFloat(ctx);
	JS_AddIntrinsicBigDecimal(ctx);
	JS_AddIntrinsicOperators(ctx);
	JS_EnableBignumExt(ctx, 1);
}
#else
static inline void vjsx_js_add_bignum_intrinsics(JSContext *ctx) {
	(void)ctx;
}
#endif

static inline void vjsx_js_eval_out(JSContext *ctx, const char *input, size_t input_len,
                                    const char *filename, int eval_flags, JSValue *out) {
	*out = JS_Eval(ctx, input, input_len, filename, eval_flags);
}

static inline void vjsx_js_eval_function_out(JSContext *ctx, JSValue func_obj, JSValue *out) {
	*out = JS_EvalFunction(ctx, func_obj);
}

static inline void vjsx_js_std_await_out(JSContext *ctx, JSValue val, JSValue *out) {
	*out = js_std_await(ctx, val);
}

static inline JSModuleDef *vjsx_js_value_to_module_def(JSValue value) {
	return (JSModuleDef *)JS_VALUE_GET_PTR(value);
}

static inline JSModuleDef *vjsx_js_module_loader(JSContext *ctx, const char *module_name, void *opaque) {
	return js_module_loader(ctx, module_name, opaque, JS_UNDEFINED);
}

#endif
