module vjsx

$if build_quickjs ? {
	#flag -I @VMODROOT/libs/include
}

$if build_quickjs ? {
	#flag -I $env('VJS_QUICKJS_PATH')
	$if !msvc {
		#flag -std=gnu11
		#flag -Dasm=__asm__
	}
	$if msvc {
		#flag -D_CRT_SECURE_NO_WARNINGS
		#flag -D_CRT_NONSTDC_NO_DEPRECATE
	}
	#flag -DNDEBUG
	$if !windows {
		#flag -D_GNU_SOURCE
	}
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
	$if linux {
		$if amd64 {
			#flag @VMODROOT/libs/qjs_linux_x64.a
		}
	} $else $if macos {
		$if amd64 {
			$compile_error('vjsx does not ship a bundled macOS x64 QuickJS archive. Set VJS_QUICKJS_PATH to a QuickJS source checkout and build with `-d build_quickjs`.')
		} $else $if arm64 {
			#flag @VMODROOT/libs/qjs_macos_arm64.a
		}
	} $else $if windows {
		$if amd64 {
			#flag @VMODROOT/libs/qjs_win_x64.a
		}
	}
}

$if !windows {
	#flag -lpthread -lm
}
#include "quickjs-libc.h"
#include "quickjs.h"
#include "vjsx_quickjs_compat.h"
