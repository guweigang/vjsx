#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_parent=$(dirname "$repo_root")
quickjs_path=${VJS_QUICKJS_PATH:-}

if [ -z "$quickjs_path" ] && [ -d "$repo_root/../quickjs" ]; then
	quickjs_path="$repo_root/../quickjs"
fi

if [ -z "$quickjs_path" ] || [ ! -d "$quickjs_path" ]; then
	echo "QuickJS source not found. Set VJS_QUICKJS_PATH to your quickjs checkout." >&2
	exit 1
fi

script_file=''
as_module=0
runtime_profile=${VJS_RUNTIME_PROFILE:-node}
args_file=$(mktemp "${TMPDIR:-/tmp}/vjsx-args.XXXXXX")

while [ $# -gt 0 ]; do
	case "$1" in
		run)
			shift
			;;
		--module|-m)
			as_module=1
			shift
			;;
		--runtime|-r)
			if [ $# -lt 2 ]; then
				echo "missing runtime profile after $1" >&2
				exit 1
			fi
			runtime_profile=$2
			shift 2
			;;
		--help|-h)
			echo "Usage: vjsx run [--module|-m] [--runtime|-r <node|script|browser>] <script.js>"
			echo "   or: vjsx [--module|-m] [--runtime|-r <node|script|browser>] <script.js>"
			exit 0
			;;
		-*)
			echo "unknown flag: $1" >&2
			exit 1
			;;
		*)
			if [ -n "$script_file" ]; then
				printf '%s\n' "$1" >> "$args_file"
				shift
				continue
			fi
			script_file=$1
			shift
			;;
	esac
done

case "$runtime_profile" in
	node|script|browser)
		:
		;;
	*)
		echo "unknown runtime profile: $runtime_profile" >&2
		echo "expected one of: node, script, browser" >&2
		exit 1
		;;
esac

if [ "$runtime_profile" = "browser" ] && [ "$as_module" -ne 1 ]; then
	echo "browser runtime requires module mode" >&2
	echo "use --module with --runtime browser" >&2
	exit 1
fi

if [ -z "$script_file" ]; then
	echo "missing script path" >&2
	exit 1
fi

case "$script_file" in
	*.mjs)
		as_module=1
		;;
	*.js|*.cjs|*.ts|*.cts)
		:
		;;
	*.mts)
		as_module=1
		;;
	*)
		echo "unsupported script type: $script_file" >&2
		echo "expected a .js, .mjs, .cjs, .ts, .mts, or .cts file" >&2
		exit 1
		;;
esac

case "$script_file" in
	/*)
		:
		;;
	*)
		script_dir=$(CDPATH= cd -- "$(dirname "$script_file")" && pwd)
		script_file=$script_dir/$(basename "$script_file")
		;;
esac

cleanup() {
	rm -f "$args_file"
}
trap cleanup EXIT INT TERM

set +e
output=$(
	cd "$repo_root" && \
	VJS_QUICKJS_PATH="$quickjs_path" \
	VJS_SCRIPT_FILE="$script_file" \
	VJS_AS_MODULE="$as_module" \
	VJS_RUNTIME_PROFILE="$runtime_profile" \
	VJS_ARGS_FILE="$args_file" \
		VJS_REPO_ROOT="$repo_root" \
	VCACHE="${VCACHE:-/tmp/vcache}" \
	sh -c 'v ${VJS_V_FLAGS:-} -d build_quickjs run ./cli_runner_bin' 2>&1
)
status=$?
set -e

printf '%s\n' "$output"
exit $status
