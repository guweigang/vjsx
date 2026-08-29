#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export VMODULES="${VMODULES:-$repo_root/.cache/vmodules}"
mkdir -p "$VMODULES"
out=${VJS_OUT:-"$repo_root/bin/vjsx"}
app_runner_out=${VJS_APP_RUNNER_OUT:-"$(dirname "$out")/vjsx-app-runner"}
quickjs_path=${VJS_QUICKJS_PATH:-}
require_static_crypto=${VJS_REQUIRE_STATIC_CRYPTO:-0}

if [ -z "$quickjs_path" ]; then
  quickjs_path=$(VJS_QUICKJS_WORK_ROOT="${VJS_QUICKJS_WORK_ROOT:-$repo_root}" "$repo_root/scripts/ensure-quickjs.sh")
fi

mkdir -p "$(dirname "$out")"
mkdir -p "$(dirname "$app_runner_out")"

find_libcrypto_a() {
  local candidate
  if [ -n "${OPENSSL_CRYPTO_STATIC_LIB:-}" ] && [ -f "$OPENSSL_CRYPTO_STATIC_LIB" ]; then
    echo "$OPENSSL_CRYPTO_STATIC_LIB"
    return 0
  fi
  if [ -n "${OPENSSL_ROOT_DIR:-}" ] && [ -f "$OPENSSL_ROOT_DIR/lib/libcrypto.a" ]; then
    echo "$OPENSSL_ROOT_DIR/lib/libcrypto.a"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix=$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)
    if [ -n "$brew_prefix" ] && [ -f "$brew_prefix/lib/libcrypto.a" ]; then
      echo "$brew_prefix/lib/libcrypto.a"
      return 0
    fi
  fi
  for candidate in \
    /opt/homebrew/opt/openssl@3/lib/libcrypto.a \
    /opt/homebrew/opt/openssl/lib/libcrypto.a \
    /opt/homebrew/lib/libcrypto.a \
    /usr/local/opt/openssl@3/lib/libcrypto.a \
    /usr/local/opt/openssl/lib/libcrypto.a \
    /usr/local/lib/libcrypto.a \
    /usr/lib/x86_64-linux-gnu/libcrypto.a \
    /usr/lib/aarch64-linux-gnu/libcrypto.a \
    /usr/lib64/libcrypto.a \
    /usr/lib/libcrypto.a; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

v_args=()
if [ -n "${VJS_V_FLAGS:-}" ]; then
  # Split user-provided flags by whitespace into array
  read -r -a custom_flags <<< "${VJS_V_FLAGS}"
  v_args=("${custom_flags[@]}")
fi

has_cc=0
if [ "${#v_args[@]}" -gt 0 ]; then
  for arg in "${v_args[@]}"; do
    case "$arg" in
      -cc|-cc=*)
        has_cc=1
        break
        ;;
    esac
  done
fi

if [ "$has_cc" -eq 0 ]; then
  v_args+=(-cc clang)
fi

crypto_static_a=$(find_libcrypto_a || true)
if [ -n "$crypto_static_a" ]; then
  static_dir="$repo_root/.cache/static-crypto"
  mkdir -p "$static_dir"
  ln -sf "$crypto_static_a" "$static_dir/libcrypto.a"
  v_args+=(-cflags "-L$static_dir")
elif [ "$require_static_crypto" = "1" ]; then
  echo "Static libcrypto is required but libcrypto.a was not found" >&2
  echo "Set OPENSSL_CRYPTO_STATIC_LIB to the absolute archive path" >&2
  exit 1
fi

cd "$repo_root"
VJS_QUICKJS_PATH="$quickjs_path" \
  v "${v_args[@]}" -prod -d build_quickjs -o "$out" ./cli_runner_bin
VJS_QUICKJS_PATH="$quickjs_path" \
  v "${v_args[@]}" -prod -d build_quickjs -o "$app_runner_out" ./app_runner_bin

check_dynamic_crypto() {
  local binary=$1
  local dependency=''
  case "$(uname -s)" in
    Darwin)
      if command -v otool >/dev/null 2>&1; then
        dependency=$(otool -L "$binary" | grep 'libcrypto.*dylib' || true)
      fi
      ;;
    Linux)
      if command -v ldd >/dev/null 2>&1; then
        dependency=$(ldd "$binary" 2>/dev/null | grep 'libcrypto\.so' || true)
      fi
      ;;
  esac
  if [ -z "$dependency" ]; then
    return 0
  fi
  if [ "$require_static_crypto" = "1" ]; then
    echo "$binary unexpectedly depends on dynamic libcrypto: $dependency" >&2
    return 1
  fi
  echo "Warning: $binary depends on dynamic libcrypto: $dependency" >&2
}

check_dynamic_crypto "$out"
check_dynamic_crypto "$app_runner_out"

echo "$out"
