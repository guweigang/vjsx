#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work_root=${VJS_QUICKJS_WORK_ROOT:-${VJS_HOST_ROOT:-$PWD}}
quickjs_dir=${QUICKJS_DIR:-"$work_root/.deps/quickjs"}
quickjs_repo=${QUICKJS_REPO:-https://github.com/quickjs-ng/quickjs}
quickjs_ref=${QUICKJS_REF:-master}

is_quickjs_ng_checkout() {
  [ -f "$1/quickjs.c" ] &&
    [ -f "$1/quickjs-c-atomics.h" ] &&
    grep -q 'QJS_VERSION_MAJOR' "$1/quickjs.h" 2>/dev/null
}

if ! is_quickjs_ng_checkout "$quickjs_dir"; then
  rm -rf "$quickjs_dir"
  git clone --depth 1 --branch "$quickjs_ref" "$quickjs_repo" "$quickjs_dir"
fi

if ! is_quickjs_ng_checkout "$quickjs_dir"; then
  echo "quickjs source checkout is not compatible with vjsx at: $quickjs_dir" >&2
  exit 1
fi

echo "$quickjs_dir"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "quickjs_dir=$quickjs_dir" >> "$GITHUB_OUTPUT"
fi
