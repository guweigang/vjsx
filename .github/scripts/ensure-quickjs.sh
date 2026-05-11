#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
"$repo_root/scripts/ensure-quickjs.sh"
