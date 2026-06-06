#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-"$SOURCE_DIR/build-wasm"}"
QT_WASM_PREFIX="${QT_WASM_PREFIX:-}"
QT_WASM_TOOLCHAIN="${QT_WASM_TOOLCHAIN:-}"
QT_HOST_PREFIX="${QT_HOST_PREFIX:-}"
DEFAULT_LOCALE="${GCOMPRIS_WASM_DEFAULT_LOCALE:-en_US}"
DOWNLOAD_ASSETS="${DOWNLOAD_ASSETS:-words,music,en_US}"

# ── Emscripten ────────────────────────────────────────────────────────────────
# Source emsdk if emcc is not already on PATH.
if ! command -v emcc >/dev/null 2>&1; then
  for emsdk_sh in \
    "$HOME/emsdk/emsdk_env.sh" \
    "/opt/emsdk/emsdk_env.sh"; do
    if [[ -f "$emsdk_sh" ]]; then
      # shellcheck source=/dev/null
      source "$emsdk_sh" --quiet 2>/dev/null || source "$emsdk_sh" 2>/dev/null || true
      break
    fi
  done
fi
if ! command -v emcc >/dev/null 2>&1; then
  cat >&2 <<'EOF'
emcc not found. Install Emscripten 3.1.70:
  git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
  ~/emsdk/emsdk install 3.1.70
  ~/emsdk/emsdk activate 3.1.70
  source ~/emsdk/emsdk_env.sh
EOF
  exit 2
fi

# ── Qt host tools ─────────────────────────────────────────────────────────────
# lrelease/lconvert (for .qm files) and rcc must come from the native host Qt,
# not the WASM kit. Auto-detect from ~/Qt if not already on PATH.
if ! command -v lrelease >/dev/null 2>&1; then
  for candidate_dir in \
    "$HOME/Qt/6.9.1/gcc_64/bin" \
    "$HOME/Qt/6.9.0/gcc_64/bin" \
    "$HOME/Qt/6.8.3/gcc_64/bin"; do
    if [[ -x "$candidate_dir/lrelease" ]]; then
      export PATH="$candidate_dir:$PATH"
      break
    fi
  done
fi

# ── Qt WASM toolchain ─────────────────────────────────────────────────────────
if [[ -z "$QT_WASM_TOOLCHAIN" ]]; then
  if [[ -n "$QT_WASM_PREFIX" ]]; then
    QT_WASM_TOOLCHAIN="$QT_WASM_PREFIX/lib/cmake/Qt6/qt.toolchain.cmake"
  else
    for candidate in \
      "$HOME/Qt/6.9.1/wasm_singlethread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.9.1/wasm_multithread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.9.0/wasm_singlethread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.9.0/wasm_multithread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.8.3/wasm_singlethread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.8.0/wasm_singlethread/lib/cmake/Qt6/qt.toolchain.cmake"; do
      if [[ -f "$candidate" ]]; then
        QT_WASM_TOOLCHAIN="$candidate"
        break
      fi
    done
  fi
fi

if [[ -z "$QT_WASM_TOOLCHAIN" || ! -f "$QT_WASM_TOOLCHAIN" ]]; then
  cat >&2 <<EOF
Could not find a Qt for WebAssembly CMake toolchain.

Set one of:
  QT_WASM_TOOLCHAIN=/path/to/qt.toolchain.cmake
  QT_WASM_PREFIX=/path/to/Qt/<version>/<wasm-kit>

Example:
  QT_WASM_PREFIX="\$HOME/Qt/6.9.0/wasm_singlethread" tools/build-wasm-pwa.sh
EOF
  exit 2
fi

# Resolve the host Qt prefix (needed by Qt's WASM toolchain to locate host tools).
if [[ -z "$QT_HOST_PREFIX" ]]; then
  _wasm_dir="$(dirname "$QT_WASM_TOOLCHAIN")/../../../.."
  _wasm_ver="$(basename "$(cd "$_wasm_dir" && pwd)")"
  for candidate_host in \
    "$(cd "$_wasm_dir/.." && pwd)/gcc_64" \
    "$HOME/Qt/$_wasm_ver/gcc_64" \
    "$HOME/Qt/6.9.1/gcc_64"; do
    if [[ -f "$candidate_host/bin/qmake" || -f "$candidate_host/bin/qmake6" ]]; then
      QT_HOST_PREFIX="$candidate_host"
      break
    fi
  done
fi

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$QT_WASM_TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SERVER=OFF \
  -DPACKAGE_GCOMPRIS=OFF \
  -DWITH_DOWNLOAD=ON \
  -DGCOMPRIS_WASM_PWA=ON \
  -DGCOMPRIS_WASM_DEFAULT_LOCALE="$DEFAULT_LOCALE" \
  -DDOWNLOAD_ASSETS="$DOWNLOAD_ASSETS" \
  ${QT_HOST_PREFIX:+-DQT_HOST_PATH="$QT_HOST_PREFIX"}

cmake --build "$BUILD_DIR" --target wasm_pwa_dist

cat <<EOF

PWA build complete:
  $BUILD_DIR/pwa

Serve locally (localhost only):
  python3 -m http.server 8000 -d "$BUILD_DIR/pwa"
  # http://localhost:8000/

Serve on Tailscale (flywheel1) with automatic HTTPS:
  tools/serve-wasm-pwa.sh
  # https://flywheel1.tail704fb4.ts.net/
EOF
