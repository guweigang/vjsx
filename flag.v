module vjsx

$if link_quickjs ? {
	#flag -I $env('VJS_QUICKJS_PATH')
	#flag -I @VMODROOT/libs/include
} $else $if build_quickjs ? {
	#flag -I $env('VJS_QUICKJS_PATH')
	#flag -I @VMODROOT/libs/include
}

// vjsx_quickjs_compat.h uses C11 atomics for the interrupt handler state.
// Keep these flags common to source and prebuilt QuickJS builds: Windows
// release binaries use msvc together with `link_quickjs`.
$if msvc {
	#flag /std:c11
	#flag /experimental:c11atomics
}

$if link_quickjs ? {
	$if quickjs_legacy ? {
	} $else {
		#flag -DVJSX_QUICKJS_NG
	}
	#flag -DNDEBUG
	#flag -DCONFIG_BIGNUM
	#flag -DCONFIG_VERSION="local"
	#flag $env('VJS_QUICKJS_LIB_PATH')
	$if linux {
		#flag -ldl
	}
} $else $if build_quickjs ? {
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
	$compile_error('vjsx no longer uses bundled QuickJS archives. Set VJS_QUICKJS_PATH to a compatible source checkout and build with `-d build_quickjs`, or set VJS_QUICKJS_LIB_PATH and build with `-d link_quickjs` to link a prebuilt quickjs-ng static library.')
}

$if !windows {
	#flag -lpthread -lm
}
#include "quickjs-libc.h"
#include "quickjs.h"
#include "vjsx_quickjs_compat.h"
