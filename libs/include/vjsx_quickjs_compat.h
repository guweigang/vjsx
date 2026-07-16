#ifndef VJSX_QUICKJS_COMPAT_H
#define VJSX_QUICKJS_COMPAT_H

#include <stdlib.h>
#include <string.h>

#include "quickjs.h"

#if defined(VJSX_QUICKJS_NG)
#define JS_IsArray(ctx, val) JS_IsArray(val)
#define JS_IsBigInt(ctx, val) JS_IsBigInt(val)
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
	char *input_copy = NULL;
	char *filename_copy = NULL;
	if (input_len > 0) {
		input_copy = (char *)malloc(input_len + 1);
		if (input_copy == NULL) {
			*out = JS_ThrowOutOfMemory(ctx);
			return;
		}
		memcpy(input_copy, input, input_len);
		input_copy[input_len] = '\0';
	} else {
		input_copy = (char *)malloc(1);
		if (input_copy == NULL) {
			*out = JS_ThrowOutOfMemory(ctx);
			return;
		}
		input_copy[0] = '\0';
	}
	if (filename != NULL) {
		size_t filename_len = strlen(filename);
		filename_copy = (char *)malloc(filename_len + 1);
		if (filename_copy == NULL) {
			free(input_copy);
			*out = JS_ThrowOutOfMemory(ctx);
			return;
		}
		memcpy(filename_copy, filename, filename_len + 1);
	}
	*out = JS_Eval(ctx, input_copy, input_len, filename_copy != NULL ? filename_copy : "<input>",
	               eval_flags);
	free(filename_copy);
	free(input_copy);
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
