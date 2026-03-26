#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
quickjs_dir=${QUICKJS_DIR:-"$repo_root/../quickjs"}
quickjs_repo=${QUICKJS_REPO:-https://github.com/bellard/quickjs}
quickjs_ref=${QUICKJS_REF:-master}

if [ ! -f "$quickjs_dir/quickjs.c" ]; then
  rm -rf "$quickjs_dir"
  git clone --depth 1 --branch "$quickjs_ref" "$quickjs_repo" "$quickjs_dir"
fi

if [ ! -f "$quickjs_dir/quickjs.c" ]; then
  echo "QuickJS source is missing quickjs.c at: $quickjs_dir" >&2
  exit 1
fi

echo "Using QuickJS source at $quickjs_dir"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "quickjs_dir=$quickjs_dir" >> "$GITHUB_OUTPUT"
fi
