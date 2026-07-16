#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work_root=${VJS_QUICKJS_WORK_ROOT:-${VJS_HOST_ROOT:-$PWD}}
if [ -n "${QUICKJS_DIR:-}" ]; then
  quickjs_dir="$QUICKJS_DIR"
  quickjs_dir_explicit=1
else
  quickjs_dir="$work_root/.deps/quickjs"
  quickjs_dir_explicit=0
fi
quickjs_repo=${QUICKJS_REPO:-https://github.com/quickjs-ng/quickjs}
quickjs_ref=${QUICKJS_REF:-v0.15.1}

is_quickjs_ng_checkout() {
  [ -f "$1/quickjs.c" ] &&
    [ -f "$1/quickjs-c-atomics.h" ] &&
    grep -q 'QJS_VERSION_MAJOR' "$1/quickjs.h" 2>/dev/null
}

quickjs_checkout_matches_ref() {
  if [ ! -d "$1/.git" ]; then
    return 1
  fi
  if [ "$quickjs_ref" = "master" ] || [ "$quickjs_ref" = "main" ]; then
    return 0
  fi
  current_ref=$(git -C "$1" describe --tags --exact-match 2>/dev/null || true)
  [ "$current_ref" = "$quickjs_ref" ]
}

if is_quickjs_ng_checkout "$quickjs_dir" && ! quickjs_checkout_matches_ref "$quickjs_dir"; then
  if [ "$quickjs_dir_explicit" -eq 1 ]; then
    echo "quickjs source checkout at $quickjs_dir is not at required ref $quickjs_ref" >&2
    echo "update it manually, or unset QUICKJS_DIR to let vjsx manage $work_root/.deps/quickjs" >&2
    exit 1
  fi
  rm -rf "$quickjs_dir"
fi

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
