#ifndef VJSX_QUICKJS_COMPAT_H
#define VJSX_QUICKJS_COMPAT_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdatomic.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <time.h>
#endif

#include "quickjs.h"

typedef struct VJSXInterruptState {
    atomic_uint_fast64_t deadline_ms;
    atomic_int reason;
} VJSXInterruptState;

enum {
    VJSX_INTERRUPT_NONE = 0,
    VJSX_INTERRUPT_CANCELLED = 1,
    VJSX_INTERRUPT_DEADLINE = 2,
};

static inline uint64_t vjsx_monotonic_time_ms(void) {
#if defined(_WIN32)
    LARGE_INTEGER frequency;
    LARGE_INTEGER counter;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&counter);
    return (uint64_t)((counter.QuadPart * 1000) / frequency.QuadPart);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
#endif
}

static inline int vjsx_interrupt_handler(JSRuntime *rt, void *opaque) {
    VJSXInterruptState *state = (VJSXInterruptState *)opaque;
    uint64_t deadline_ms;
    int expected;
    (void)rt;
    if (state == NULL) {
        return 0;
    }
    if (atomic_load_explicit(&state->reason, memory_order_acquire) != VJSX_INTERRUPT_NONE) {
        return 1;
    }
    deadline_ms = atomic_load_explicit(&state->deadline_ms, memory_order_relaxed);
    if (deadline_ms == 0 || vjsx_monotonic_time_ms() < deadline_ms) {
        return 0;
    }
    expected = VJSX_INTERRUPT_NONE;
    atomic_compare_exchange_strong_explicit(&state->reason, &expected,
                                             VJSX_INTERRUPT_DEADLINE,
                                             memory_order_acq_rel,
                                             memory_order_acquire);
    return 1;
}

static inline VJSXInterruptState *vjsx_interrupt_state_new(JSRuntime *rt) {
    VJSXInterruptState *state = (VJSXInterruptState *)malloc(sizeof(*state));
    if (state == NULL) {
        return NULL;
    }
    atomic_init(&state->deadline_ms, 0);
    atomic_init(&state->reason, VJSX_INTERRUPT_NONE);
    JS_SetInterruptHandler(rt, vjsx_interrupt_handler, state);
    return state;
}

static inline void vjsx_interrupt_state_free(JSRuntime *rt, VJSXInterruptState *state) {
    JS_SetInterruptHandler(rt, NULL, NULL);
    free(state);
}

static inline void vjsx_interrupt_set_deadline_after_ms(VJSXInterruptState *state,
                                                         uint64_t delay_ms) {
    uint64_t now_ms;
    if (state == NULL ||
        atomic_load_explicit(&state->reason, memory_order_acquire) != VJSX_INTERRUPT_NONE) {
        return;
    }
    now_ms = vjsx_monotonic_time_ms();
    atomic_store_explicit(&state->deadline_ms, now_ms + delay_ms,
                          memory_order_release);
}

static inline void vjsx_interrupt_clear_deadline(VJSXInterruptState *state) {
    if (state == NULL ||
        atomic_load_explicit(&state->reason, memory_order_acquire) != VJSX_INTERRUPT_NONE) {
        return;
    }
    atomic_store_explicit(&state->deadline_ms, 0, memory_order_release);
}

static inline void vjsx_interrupt_cancel(VJSXInterruptState *state) {
    int expected = VJSX_INTERRUPT_NONE;
    if (state == NULL) {
        return;
    }
    atomic_compare_exchange_strong_explicit(&state->reason, &expected,
                                             VJSX_INTERRUPT_CANCELLED,
                                             memory_order_acq_rel,
                                             memory_order_acquire);
}

static inline int vjsx_interrupt_reason(VJSXInterruptState *state) {
    if (state == NULL) {
        return VJSX_INTERRUPT_NONE;
    }
    return atomic_load_explicit(&state->reason, memory_order_acquire);
}

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

static inline uint8_t *vjsx_js_write_bytecode(JSContext *ctx, size_t *out_len,
                                              JSValueConst obj, int strip_source,
                                              int strip_debug) {
	int flags = JS_WRITE_OBJ_BYTECODE;
#if defined(JS_WRITE_OBJ_STRIP_SOURCE)
	if (strip_source) {
		flags |= JS_WRITE_OBJ_STRIP_SOURCE;
	}
#else
	(void)strip_source;
#endif
#if defined(JS_WRITE_OBJ_STRIP_DEBUG)
	if (strip_debug) {
		flags |= JS_WRITE_OBJ_STRIP_DEBUG;
	}
#else
	(void)strip_debug;
#endif
	return JS_WriteObject(ctx, out_len, obj, flags);
}

static inline void vjsx_js_read_bytecode_out(JSContext *ctx, const uint8_t *buf,
                                             size_t buf_len, JSValue *out) {
	*out = JS_ReadObject(ctx, buf, buf_len, JS_READ_OBJ_BYTECODE);
}

static inline const char *vjsx_quickjs_version(void) {
#if defined(VJSX_QUICKJS_NG)
	return JS_GetVersion();
#else
	return CONFIG_VERSION;
#endif
}

static inline int vjsx_js_resolve_module(JSContext *ctx, JSValueConst module_obj) {
	return JS_ResolveModule(ctx, module_obj);
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

static inline char *vjsx_js_strdup(JSContext *ctx, const char *str) {
	size_t len = strlen(str);
	char *copy = js_malloc(ctx, len + 1);
	if (copy == NULL) {
		JS_ThrowOutOfMemory(ctx);
		return NULL;
	}
	memcpy(copy, str, len + 1);
	return copy;
}

#endif
