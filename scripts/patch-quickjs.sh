#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
quickjs_source=$1
patch_dir="$repo_root/thirdparty/quickjs-patches"

patch_is_applied() {
  git -C "$quickjs_source" apply --reverse --check "$1" 2>/dev/null
}

for patch_file in "$patch_dir"/*.patch; do
  if patch_is_applied "$patch_file"; then
    continue
  fi
  # unref-timers changes the poll call used as context by await-ready-jobs.
  # Its reverse check still requires the ready-jobs guard to be present.
  if [ "$patch_file" = "$patch_dir/await-ready-jobs.patch" ] &&
    patch_is_applied "$patch_dir/unref-timers.patch"; then
    continue
  fi
  if ! git -C "$quickjs_source" apply --check "$patch_file"; then
    echo "QuickJS patch $(basename "$patch_file") no longer applies at $quickjs_source" >&2
    exit 1
  fi
  git -C "$quickjs_source" apply "$patch_file"
done
