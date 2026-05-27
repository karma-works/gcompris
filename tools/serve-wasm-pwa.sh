#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Serve the built GCompris WASM PWA and expose it on the Tailscale network.
#
# Usage:
#   tools/serve-wasm-pwa.sh
#   PORT=9000 tools/serve-wasm-pwa.sh
#   PWA_DIR=/path/to/pwa tools/serve-wasm-pwa.sh

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-"$SOURCE_DIR/build-wasm"}"
PWA_DIR="${PWA_DIR:-"$BUILD_DIR/pwa"}"
LOCAL_PORT="${PORT:-8000}"

if [[ ! -d "$PWA_DIR" ]]; then
  cat >&2 <<EOF
PWA build directory not found:
  $PWA_DIR

Run the build first:
  tools/build-wasm-pwa.sh
EOF
  exit 1
fi

if [[ ! -f "$PWA_DIR/index.html" ]]; then
  echo "Error: $PWA_DIR/index.html missing — PWA bundle looks incomplete." >&2
  exit 1
fi

# Kill any stale server already holding the port so re-runs always succeed.
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${LOCAL_PORT}/tcp" 2>/dev/null || true
  sleep 0.3
fi

# Get the Tailscale IP for this node so we can bind there directly.
TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)

# Start a Python HTTP server bound to all interfaces (0.0.0.0).
# Includes COOP/COEP headers for SharedArrayBuffer (Qt WASM multithreaded).
PWA_DIR="$PWA_DIR" LOCAL_PORT="$LOCAL_PORT" python3 -c '
import os, http.server, socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
    def log_message(self, fmt, *args):
        pass  # silence per-request noise

directory = os.environ["PWA_DIR"]
port      = int(os.environ["LOCAL_PORT"])
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", port), lambda *a, **kw: Handler(*a, directory=directory, **kw)) as srv:
    srv.serve_forever()
' &
PYTHON_PID=$!

cleanup() {
  kill "$PYTHON_PID" 2>/dev/null || true
  tailscale serve reset >/dev/null 2>&1 || true
  echo
  echo "Stopped."
}
trap cleanup EXIT INT TERM

# Wait for the server to bind.
sleep 0.5

# Collect Tailscale metadata.
TAILNET=$(tailscale status --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('CurrentTailnet',{}).get('MagicDNSSuffix',''))" 2>/dev/null || true)
TS_HOST=$(tailscale status --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('Self',{}).get('HostName','flywheel1'))" 2>/dev/null || true)

# Try to set up Tailscale HTTPS (requires "Serve" to be enabled in the admin
# console; falls back gracefully if it is not available).
TS_HTTPS_URL=""
if TS_SERVE_ERR=$(tailscale serve --bg "$LOCAL_PORT" 2>&1); then
  if [[ -n "$TAILNET" && -n "$TS_HOST" ]]; then
    TS_HTTPS_URL="https://${TS_HOST}.${TAILNET}/"
  fi
fi

echo
echo "GCompris WASM PWA is live:"
echo

if [[ -n "$TS_HTTPS_URL" ]]; then
  echo "  $TS_HTTPS_URL"
  echo "    ↑ Tailscale HTTPS — installable as PWA, service worker enabled"
  echo
fi

if [[ -n "$TS_IP" && -n "$TS_HOST" && -n "$TAILNET" ]]; then
  echo "  http://${TS_HOST}.${TAILNET}:${LOCAL_PORT}/"
  echo "  http://${TS_IP}:${LOCAL_PORT}/"
  echo "    ↑ Tailscale HTTP — app works, service worker / PWA install disabled"
  echo
fi

echo "  http://127.0.0.1:${LOCAL_PORT}/"
echo "    ↑ localhost only"
echo

if [[ -z "$TS_HTTPS_URL" ]]; then
  if echo "${TS_SERVE_ERR:-}" | grep -q "not enabled"; then
    ENABLE_URL=$(echo "$TS_SERVE_ERR" | grep -Eo 'https://[^ ]+' | head -1 || true)
    cat <<EOF
Note: Tailscale Serve (HTTPS) is not enabled on this tailnet.
For PWA install + service worker, enable it once at:
  ${ENABLE_URL:-https://login.tailscale.com/admin/machines}
Then re-run this script.

EOF
  fi
fi

echo "Press Ctrl+C to stop."
echo

wait "$PYTHON_PID"
