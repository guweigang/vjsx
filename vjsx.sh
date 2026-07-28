#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cli_cwd=$PWD
quickjs_path=${VJS_QUICKJS_PATH:-}

if [ -z "$quickjs_path" ]; then
	quickjs_path=$(VJS_QUICKJS_WORK_ROOT="${VJS_QUICKJS_WORK_ROOT:-$cli_cwd}" "$repo_root/scripts/ensure-quickjs.sh")
fi

if [ -z "$quickjs_path" ] ||
	[ ! -f "$quickjs_path/quickjs.c" ] ||
	[ ! -f "$quickjs_path/quickjs-c-atomics.h" ] ||
	! grep -q 'QJS_VERSION_MAJOR' "$quickjs_path/quickjs.h" 2>/dev/null; then
	echo "compatible QuickJS source not found. Set VJS_QUICKJS_PATH or let vjsx download its managed checkout." >&2
	exit 1
fi

vexe=${VEXE:-}
if [ -z "$vexe" ]; then
	vexe=$(command -v v || true)
fi
if [ -z "$vexe" ]; then
	echo "V compiler not found. Set VEXE or add v to PATH." >&2
	exit 1
fi

v_flags=${VJS_V_FLAGS:-}
case " $v_flags " in
	*" -cc "*|*" -cc="*|*" -cc")
		:
		;;
	*)
		v_flags="-cc clang${v_flags:+ $v_flags}"
		;;
esac

cd "$repo_root"
if [ -n "$v_flags" ]; then
	# shellcheck disable=SC2086
	exec env VJS_QUICKJS_PATH="$quickjs_path" VJS_REPO_ROOT="$repo_root" VJS_CLI_CWD="$cli_cwd" VCACHE="${VCACHE:-/tmp/vcache}" \
		"$vexe" $v_flags -d build_quickjs run ./cli_runner_bin "$@"
fi

exec env VJS_QUICKJS_PATH="$quickjs_path" VJS_REPO_ROOT="$repo_root" VJS_CLI_CWD="$cli_cwd" VCACHE="${VCACHE:-/tmp/vcache}" \
	"$vexe" -d build_quickjs run ./cli_runner_bin "$@"
