#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
quickjs_source=$1
# Keep descriptor counts distinct from poll readiness, and drain ready promise
# jobs before blocking in top-level await. Both patches are pinned and idempotent.
for patch_file in "$repo_root"/thirdparty/quickjs-patches/*.patch; do
  if git -C "$quickjs_source" apply --reverse --check "$patch_file" 2>/dev/null; then
    continue
  fi
  if ! git -C "$quickjs_source" apply --check "$patch_file"; then
    echo "QuickJS patch no longer applies; audit the new dependency before building" >&2
    exit 1
  fi
  git -C "$quickjs_source" apply "$patch_file"
done
