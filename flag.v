module vjsx

$if build_quickjs ? {
	#flag -I $env('VJS_QUICKJS_PATH')
	#flag -I @VMODROOT/libs/include
}

$if build_quickjs ? {
	$if !msvc {
		#flag -std=gnu11
		#flag -Dasm=__asm__
		$if tinyc {
			#flag -D__ATOMIC_SEQ_CST=5
		}
		$if quickjs_legacy ? {
			$if tinyc && arm64 {
				#flag -U__aarch64__
			}
		}
	}
	$if msvc {
		#flag /std:c11
		#flag /experimental:c11atomics
		#flag -D_WINSOCKAPI_
		#flag -D_CRT_SECURE_NO_WARNINGS
		#flag -D_CRT_NONSTDC_NO_DEPRECATE
	}
	$if quickjs_legacy ? {
	} $else {
		#flag -DVJSX_QUICKJS_NG
	}
	#flag -DNDEBUG
	$if !windows {
		#flag -D_GNU_SOURCE
	}
	#flag -DCONFIG_BIGNUM
	#flag -DCONFIG_VERSION="local"
	#flag $env('VJS_QUICKJS_PATH')/quickjs.c
	#flag $env('VJS_QUICKJS_PATH')/dtoa.c
	#flag $env('VJS_QUICKJS_PATH')/libregexp.c
	#flag $env('VJS_QUICKJS_PATH')/libunicode.c
	$if quickjs_legacy ? {
		#flag $env('VJS_QUICKJS_PATH')/cutils.c
	}
	#flag $env('VJS_QUICKJS_PATH')/quickjs-libc.c
	$if linux {
		#flag -ldl
	}
} $else {
	$compile_error('vjsx no longer uses bundled QuickJS archives. Set VJS_QUICKJS_PATH to a compatible source checkout and build with `-d build_quickjs`, or use `scripts/ensure-quickjs.sh` to prepare the managed checkout.')
}

$if !windows {
	#flag -lpthread -lm
}
#include "quickjs-libc.h"
#include "quickjs.h"
#include "vjsx_quickjs_compat.h"
