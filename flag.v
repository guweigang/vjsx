module vjsx

$if build_quickjs ? {
	#flag -I @VMODROOT/libs/include
}

$if build_quickjs ? {
	#flag -I $env('VJS_QUICKJS_PATH')
	#flag -std=gnu11
	#flag -Dasm=__asm__
	#flag -DNDEBUG
	#flag -D_GNU_SOURCE
	#flag -DCONFIG_BIGNUM
	#flag -DCONFIG_VERSION='"local"'
	#flag $env('VJS_QUICKJS_PATH')/quickjs.c
	#flag $env('VJS_QUICKJS_PATH')/dtoa.c
	#flag $env('VJS_QUICKJS_PATH')/libregexp.c
	#flag $env('VJS_QUICKJS_PATH')/libunicode.c
	#flag $env('VJS_QUICKJS_PATH')/cutils.c
	#flag $env('VJS_QUICKJS_PATH')/quickjs-libc.c
	$if linux {
		#flag -ldl
	}
} $else {
	#flag -I @VMODROOT/libs/include

	$if tinyc && !windows {
		// misc for tcc
		#flag @VMODROOT/libs/misc/divti3.c
		#flag @VMODROOT/libs/misc/udivti3.c
		#flag @VMODROOT/libs/misc/udivmodti4.c
	}
	$if x64 {
		$if linux {
			#flag @VMODROOT/libs/qjs_linux_x64.a
		} $else $if macos {
			#flag @VMODROOT/libs/qjs_macos_x64.a
		} $else $if windows {
			#flag @VMODROOT/libs/qjs_win_x64.a
		}
	}
}

#flag -lpthread -lm
#include "quickjs-libc.h"
#include "quickjs.h"
#include "vjsx_quickjs_compat.h"
