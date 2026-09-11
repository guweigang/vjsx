#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export VMODULES="${VMODULES:-$repo_root/.cache/vmodules}"
mkdir -p "$VMODULES"
out=${VJS_OUT:-"$repo_root/bin/vjsx"}
quickjs_path=${VJS_QUICKJS_PATH:-}
require_static_crypto=${VJS_REQUIRE_STATIC_CRYPTO:-0}

if [ -z "$quickjs_path" ]; then
  quickjs_path=$(VJS_QUICKJS_WORK_ROOT="${VJS_QUICKJS_WORK_ROOT:-$repo_root}" "$repo_root/scripts/ensure-quickjs.sh")
fi

mkdir -p "$(dirname "$out")"

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

find_libssl_a() {
  local candidate
  if [ -n "${OPENSSL_SSL_STATIC_LIB:-}" ] && [ -f "$OPENSSL_SSL_STATIC_LIB" ]; then
    echo "$OPENSSL_SSL_STATIC_LIB"
    return 0
  fi
  if [ -n "${OPENSSL_ROOT_DIR:-}" ] && [ -f "$OPENSSL_ROOT_DIR/lib/libssl.a" ]; then
    echo "$OPENSSL_ROOT_DIR/lib/libssl.a"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix=$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)
    if [ -n "$brew_prefix" ] && [ -f "$brew_prefix/lib/libssl.a" ]; then
      echo "$brew_prefix/lib/libssl.a"
      return 0
    fi
  fi
  for candidate in \
    /opt/homebrew/opt/openssl@3/lib/libssl.a \
    /opt/homebrew/opt/openssl/lib/libssl.a \
    /opt/homebrew/lib/libssl.a \
    /usr/local/opt/openssl@3/lib/libssl.a \
    /usr/local/opt/openssl/lib/libssl.a \
    /usr/local/lib/libssl.a \
    /usr/lib/x86_64-linux-gnu/libssl.a \
    /usr/lib/aarch64-linux-gnu/libssl.a \
    /usr/lib64/libssl.a \
    /usr/lib/libssl.a; do
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

has_use_openssl=0
if [ "${#v_args[@]}" -gt 0 ]; then
  for ((i = 0; i < ${#v_args[@]}; i++)); do
    if [ "${v_args[$i]}" = "-d=use_openssl" ] || [ "${v_args[$i]}" = "-duse_openssl" ]; then
      has_use_openssl=1
      break
    fi
    if [ "${v_args[$i]}" = "-d" ] && [ "$((i + 1))" -lt "${#v_args[@]}" ] && [ "${v_args[$((i + 1))]}" = "use_openssl" ]; then
      has_use_openssl=1
      break
    fi
  done
fi
if [ "$has_use_openssl" -eq 0 ]; then
  v_args+=(-d use_openssl)
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
ssl_static_a=$(find_libssl_a || true)
if [ -n "$crypto_static_a" ] && [ -n "$ssl_static_a" ]; then
  static_dir="$repo_root/.cache/static-crypto"
  mkdir -p "$static_dir"
  ln -sf "$crypto_static_a" "$static_dir/libcrypto.a"
  ln -sf "$ssl_static_a" "$static_dir/libssl.a"
  # V prepends the CFLAGS environment value before module and pkg-config flags.
  # Giving this directory first priority makes every later `-lssl -lcrypto`
  # resolve to the archives on Unix toolchains.
  export CFLAGS="-L$static_dir${CFLAGS:+ $CFLAGS}"
  export LIBRARY_PATH="$static_dir${LIBRARY_PATH:+:$LIBRARY_PATH}"
  echo "Using static OpenSSL: $ssl_static_a $crypto_static_a" >&2
elif [ "$require_static_crypto" = "1" ]; then
  echo "Static OpenSSL is required but libssl.a or libcrypto.a was not found" >&2
  echo "Set OPENSSL_SSL_STATIC_LIB and OPENSSL_CRYPTO_STATIC_LIB to the absolute archive paths" >&2
  exit 1
fi

cd "$repo_root"
VJS_QUICKJS_PATH="$quickjs_path" \
  v "${v_args[@]}" -prod -d build_quickjs -o "$out" ./cli_runner_bin

check_dynamic_openssl() {
  local binary=$1
  local dependency=''
  case "$(uname -s)" in
    Darwin)
      if command -v otool >/dev/null 2>&1; then
        dependency=$(otool -L "$binary" | grep -E 'lib(ssl|crypto).*dylib' || true)
      fi
      ;;
    Linux)
      if command -v ldd >/dev/null 2>&1; then
        dependency=$(ldd "$binary" 2>/dev/null | grep -E 'lib(ssl|crypto)\.so' || true)
      fi
      ;;
  esac
  if [ -z "$dependency" ]; then
    return 0
  fi
  if [ "$require_static_crypto" = "1" ]; then
    echo "$binary unexpectedly depends on dynamic OpenSSL: $dependency" >&2
    return 1
  fi
  echo "Warning: $binary depends on dynamic OpenSSL: $dependency" >&2
}

check_dynamic_openssl "$out"

echo "$out"
