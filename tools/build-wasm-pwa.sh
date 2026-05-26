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
DEFAULT_LOCALE="${GCOMPRIS_WASM_DEFAULT_LOCALE:-de_DE}"
DOWNLOAD_ASSETS="${DOWNLOAD_ASSETS:-words,music,de}"

if [[ -z "$QT_WASM_TOOLCHAIN" ]]; then
  if [[ -n "$QT_WASM_PREFIX" ]]; then
    QT_WASM_TOOLCHAIN="$QT_WASM_PREFIX/lib/cmake/Qt6/qt.toolchain.cmake"
  else
    for candidate in \
      "$HOME/Qt/6.9.0/wasm_multithread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.9.0/wasm_singlethread/lib/cmake/Qt6/qt.toolchain.cmake" \
      "$HOME/Qt/6.8.0/wasm_multithread/lib/cmake/Qt6/qt.toolchain.cmake" \
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

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$QT_WASM_TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SERVER=OFF \
  -DPACKAGE_GCOMPRIS=OFF \
  -DWITH_DOWNLOAD=OFF \
  -DGCOMPRIS_WASM_PWA=ON \
  -DGCOMPRIS_WASM_DEFAULT_LOCALE="$DEFAULT_LOCALE" \
  -DDOWNLOAD_ASSETS="$DOWNLOAD_ASSETS"

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
