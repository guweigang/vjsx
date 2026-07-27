#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out=${VJS_OUT:-"$repo_root/dist/vjsx"}
quickjs_path=${VJS_QUICKJS_PATH:-}

if [ -z "$quickjs_path" ]; then
  quickjs_path=$(VJS_QUICKJS_WORK_ROOT="${VJS_QUICKJS_WORK_ROOT:-$repo_root}" "$repo_root/scripts/ensure-quickjs.sh")
fi

mkdir -p "$(dirname "$out")"

v_flags=${VJS_V_FLAGS:-}
case " $v_flags " in
  *" -cc "*|*" -cc="*|*" -cc")
    ;;
  *)
    v_flags="-cc clang${v_flags:+ $v_flags}"
    ;;
esac

cd "$repo_root"
VJS_QUICKJS_PATH="$quickjs_path" \
  v ${v_flags:-} -prod -d build_quickjs -o "$out" ./cli_runner_bin

echo "$out"
