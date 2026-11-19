#ifndef VJSX_QUICKJS_COMPAT_H
#define VJSX_QUICKJS_COMPAT_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <stdatomic.h>
#include <time.h>
#endif

#include "quickjs.h"

typedef struct VJSXInterruptState {
#if defined(_WIN32)
    volatile LONG64 deadline_ms;
    volatile LONG reason;
    void *volatile target_ctx;
#else
    atomic_uint_fast64_t deadline_ms;
    atomic_int reason;
    atomic_uintptr_t target_ctx;
#endif
} VJSXInterruptState;

enum {
    VJSX_INTERRUPT_NONE = 0,
    VJSX_INTERRUPT_CANCELLED = 1,
    VJSX_INTERRUPT_DEADLINE = 2,
};

static inline int vjsx_atomic_load_reason(VJSXInterruptState *state) {
#if defined(_WIN32)
    return (int)InterlockedCompareExchange(&state->reason, 0, 0);
#else
    return atomic_load_explicit(&state->reason, memory_order_acquire);
#endif
}

static inline uint64_t vjsx_atomic_load_deadline(VJSXInterruptState *state) {
#if defined(_WIN32)
    return (uint64_t)InterlockedCompareExchange64(&state->deadline_ms, 0, 0);
#else
    return atomic_load_explicit(&state->deadline_ms, memory_order_relaxed);
#endif
}

static inline void vjsx_atomic_store_deadline(VJSXInterruptState *state,
                                               uint64_t deadline_ms) {
#if defined(_WIN32)
    InterlockedExchange64(&state->deadline_ms, (LONG64)deadline_ms);
#else
    atomic_store_explicit(&state->deadline_ms, deadline_ms, memory_order_release);
#endif
}

static inline JSContext *vjsx_atomic_load_target_ctx(VJSXInterruptState *state) {
#if defined(_WIN32)
    return (JSContext *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&state->target_ctx, NULL, NULL);
#else
    return (JSContext *)atomic_load_explicit(&state->target_ctx,
                                             memory_order_acquire);
#endif
}

static inline void vjsx_atomic_store_target_ctx(VJSXInterruptState *state,
                                                 JSContext *ctx) {
#if defined(_WIN32)
    InterlockedExchangePointer((PVOID volatile *)&state->target_ctx, ctx);
#else
    atomic_store_explicit(&state->target_ctx, (uintptr_t)ctx,
                          memory_order_release);
#endif
}

static inline void vjsx_atomic_try_set_reason(VJSXInterruptState *state, int reason) {
#if defined(_WIN32)
    InterlockedCompareExchange(&state->reason, (LONG)reason, VJSX_INTERRUPT_NONE);
#else
    int expected = VJSX_INTERRUPT_NONE;
    atomic_compare_exchange_strong_explicit(&state->reason, &expected, reason,
                                             memory_order_acq_rel,
                                             memory_order_acquire);
#endif
}

static inline void vjsx_atomic_init(VJSXInterruptState *state) {
#if defined(_WIN32)
    InterlockedExchange64(&state->deadline_ms, 0);
    InterlockedExchange(&state->reason, VJSX_INTERRUPT_NONE);
    InterlockedExchangePointer((PVOID volatile *)&state->target_ctx, NULL);
#else
    atomic_init(&state->deadline_ms, 0);
    atomic_init(&state->reason, VJSX_INTERRUPT_NONE);
    atomic_init(&state->target_ctx, (uintptr_t)NULL);
#endif
}

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

static inline int vjsx_interrupt_handler_impl(JSContext *ctx, void *opaque) {
    VJSXInterruptState *state = (VJSXInterruptState *)opaque;
    JSContext *target_ctx;
    uint64_t deadline_ms;
    if (state == NULL) {
        return 0;
    }
    target_ctx = vjsx_atomic_load_target_ctx(state);
    if (ctx != NULL && target_ctx != NULL && ctx != target_ctx) {
        return 0;
    }
    if (vjsx_atomic_load_reason(state) != VJSX_INTERRUPT_NONE) {
        return 1;
    }
    deadline_ms = vjsx_atomic_load_deadline(state);
    if (deadline_ms == 0 || vjsx_monotonic_time_ms() < deadline_ms) {
        return 0;
    }
    vjsx_atomic_try_set_reason(state, VJSX_INTERRUPT_DEADLINE);
    return 1;
}

#if defined(VJSX_QUICKJS_NG) && \
    (QJS_VERSION_MAJOR > 0 || QJS_VERSION_MINOR >= 18)
static inline int vjsx_interrupt_handler(JSContext *ctx, void *opaque) {
    return vjsx_interrupt_handler_impl(ctx, opaque);
}
#else
static inline int vjsx_interrupt_handler(JSRuntime *rt, void *opaque) {
    (void)rt;
    return vjsx_interrupt_handler_impl(NULL, opaque);
}
#endif

static inline VJSXInterruptState *vjsx_interrupt_state_new(JSRuntime *rt) {
    VJSXInterruptState *state = (VJSXInterruptState *)malloc(sizeof(*state));
    if (state == NULL) {
        return NULL;
    }
    vjsx_atomic_init(state);
    JS_SetInterruptHandler(rt, vjsx_interrupt_handler, state);
    return state;
}

static inline void vjsx_interrupt_state_free(JSRuntime *rt, VJSXInterruptState *state) {
    JS_SetInterruptHandler(rt, NULL, NULL);
    free(state);
}

static inline void vjsx_interrupt_set_deadline_after_ms(VJSXInterruptState *state,
                                                         JSContext *ctx,
                                                         uint64_t delay_ms) {
    uint64_t now_ms;
    if (state == NULL ||
        vjsx_atomic_load_reason(state) != VJSX_INTERRUPT_NONE) {
        return;
    }
    now_ms = vjsx_monotonic_time_ms();
    vjsx_atomic_store_target_ctx(state, ctx);
    vjsx_atomic_store_deadline(state, now_ms + delay_ms);
}

static inline void vjsx_interrupt_clear_deadline(VJSXInterruptState *state,
                                                  JSContext *ctx) {
    if (state == NULL ||
        vjsx_atomic_load_reason(state) != VJSX_INTERRUPT_NONE) {
        return;
    }
    if (vjsx_atomic_load_target_ctx(state) != ctx) {
        return;
    }
    vjsx_atomic_store_deadline(state, 0);
    vjsx_atomic_store_target_ctx(state, NULL);
}

static inline void vjsx_interrupt_cancel(VJSXInterruptState *state,
                                          JSContext *ctx) {
    if (state == NULL) {
        return;
    }
    vjsx_atomic_store_target_ctx(state, ctx);
    vjsx_atomic_try_set_reason(state, VJSX_INTERRUPT_CANCELLED);
}

static inline int vjsx_interrupt_reason(VJSXInterruptState *state,
                                         JSContext *ctx) {
    if (state == NULL) {
        return VJSX_INTERRUPT_NONE;
    }
    if (ctx != NULL && vjsx_atomic_load_target_ctx(state) != ctx) {
        return VJSX_INTERRUPT_NONE;
    }
    return vjsx_atomic_load_reason(state);
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

static inline JSValue vjsx_js_promise_then(JSContext *ctx, JSValueConst promise,
                                           JSValueConst on_fulfilled,
                                           JSValueConst on_rejected) {
#if defined(VJSX_QUICKJS_NG)
    return JS_PromiseThen(ctx, promise, on_fulfilled, on_rejected);
#else
    JSValue then = JS_GetPropertyStr(ctx, promise, "then");
    JSValue args[2] = { JS_DupValue(ctx, on_fulfilled),
                        JS_DupValue(ctx, on_rejected) };
    JSValue result;
    if (JS_IsException(then)) {
        JS_FreeValue(ctx, args[0]);
        JS_FreeValue(ctx, args[1]);
        return then;
    }
    result = JS_Call(ctx, then, promise, 2, args);
    JS_FreeValue(ctx, args[0]);
    JS_FreeValue(ctx, args[1]);
    JS_FreeValue(ctx, then);
    return result;
#endif
}

typedef void VJSXDynamicImportFunc(JSContext *ctx, const char *basename,
                                   const char *filename, JSValue token,
                                   JSValueConst attributes, void *opaque);

static inline int vjsx_set_dynamic_import_func(JSRuntime *rt,
                                                VJSXDynamicImportFunc *func,
                                                void *opaque) {
#if defined(VJSX_QUICKJS_NG) && \
    (QJS_VERSION_MAJOR > 0 || QJS_VERSION_MINOR >= 18)
    JS_SetDynamicImportFunc(rt, (JSDynamicImportFunc *)func, opaque);
    return 1;
#else
    (void)rt;
    (void)func;
    (void)opaque;
    return 0;
#endif
}

static inline void vjsx_js_load_module_out(JSContext *ctx,
                                            const char *basename,
                                            const char *filename,
                                            JSValueConst attributes,
                                            JSValue *out) {
#if defined(VJSX_QUICKJS_NG) && \
    (QJS_VERSION_MAJOR > 0 || QJS_VERSION_MINOR >= 18)
    *out = JS_LoadModule(ctx, basename, filename, attributes);
#else
    (void)basename;
    (void)filename;
    (void)attributes;
    *out = JS_ThrowReferenceError(ctx,
        "asynchronous dynamic import is not supported by this QuickJS build");
#endif
}

static inline int vjsx_js_finish_dynamic_import(JSContext *ctx, JSValue token,
                                                 JSValue promise) {
#if defined(VJSX_QUICKJS_NG) && \
    (QJS_VERSION_MAJOR > 0 || QJS_VERSION_MINOR >= 18)
    JSValue exception = JS_UNDEFINED;
    if (JS_IsException(promise)) {
        exception = JS_GetException(ctx);
    }
    return JS_FinishDynamicImport(ctx, token, promise, exception);
#else
    JS_FreeValue(ctx, token);
    JS_FreeValue(ctx, promise);
    return -1;
#endif
}

static inline int vjsx_js_reject_dynamic_import(JSContext *ctx, JSValue token,
                                                 const char *message) {
#if defined(VJSX_QUICKJS_NG) && \
    (QJS_VERSION_MAJOR > 0 || QJS_VERSION_MINOR >= 18)
    JSValue exception;
    JS_ThrowReferenceError(ctx, "%s", message);
    exception = JS_GetException(ctx);
    return JS_FinishDynamicImport(ctx, token, JS_EXCEPTION, exception);
#else
    (void)message;
    JS_FreeValue(ctx, token);
    return -1;
#endif
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

static inline int vjsx_js_value_is_module(JSValueConst value) {
	return JS_VALUE_GET_TAG(value) == JS_TAG_MODULE;
}

static inline void vjsx_js_get_module_def_namespace_out(JSContext *ctx,
                                                         JSModuleDef *module_def,
                                                         JSValue *out) {
	*out = JS_GetModuleNamespace(ctx, module_def);
}

static inline void vjsx_js_throw_bundle_module_not_found(JSContext *ctx,
                                                         const char *module_name) {
	JS_ThrowReferenceError(ctx, "bundle module not found: %s", module_name);
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
	/*
	 * quickjs-ng's js_std_await executes one promise job and then immediately
	 * enters js_os_poll. A future timer can therefore block later microtasks
	 * that are already queued. Drain the current job queue before allowing the
	 * std loop to sleep so fast host promises are not starved by long timers.
	 */
	JSRuntime *rt = JS_GetRuntime(ctx);
	while (JS_IsJobPending(rt)) {
		JSContext *job_ctx = NULL;
		if (JS_ExecutePendingJob(rt, &job_ctx) <= 0) {
			break;
		}
	}
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
