#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

repo_root="../../.."
port="${MOCK_OPENAI_PORT:-19191}"
vjsx_bin="${VJSX_BIN:-$repo_root/vjsx}"

npm ci --ignore-scripts

node ./mock-openai-server.mjs &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM

sleep 1

MOCK_OPENAI_BASE_URL="http://127.0.0.1:${port}/v1" \
  "$vjsx_bin" --runtime node --module ./smoke.mts
