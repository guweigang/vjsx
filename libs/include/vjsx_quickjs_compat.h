#ifndef VJSX_QUICKJS_COMPAT_H
#define VJSX_QUICKJS_COMPAT_H

#include "quickjs.h"

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

#endif
