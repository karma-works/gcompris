#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Serve the built GCompris WASM PWA and expose it on the Tailscale network
# (hostname: flywheel1) with automatic HTTPS via tailscale serve.
#
# Usage:
#   tools/serve-wasm-pwa.sh
#   PORT=9000 tools/serve-wasm-pwa.sh    # use a different local port
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

# Start a local HTTP server that adds the COOP/COEP headers required for
# SharedArrayBuffer (Qt WASM multithreaded builds) and sets application/wasm.
# The server binds to 127.0.0.1 only; tailscale serve provides public HTTPS.
PWA_DIR="$PWA_DIR" LOCAL_PORT="$LOCAL_PORT" python3 -c '
import os, http.server, socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
    def log_message(self, fmt, *args):
        pass  # silence per-request noise; errors still go to stderr

directory = os.environ["PWA_DIR"]
port      = int(os.environ["LOCAL_PORT"])
addr      = ("127.0.0.1", port)
with socketserver.TCPServer(addr, lambda *a, **kw: Handler(*a, directory=directory, **kw)) as srv:
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

# Give the Python server a moment to bind before tailscale tests it.
sleep 0.5

# Expose via Tailscale HTTPS (flywheel1.<tailnet>.ts.net → 127.0.0.1:LOCAL_PORT).
tailscale serve --bg "$LOCAL_PORT" >/dev/null

# Derive the public URL from tailscale status.
TAILNET=$(tailscale status --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('CurrentTailnet',{}).get('MagicDNSSuffix',''))" 2>/dev/null || true)
TS_HOST=$(tailscale status --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('Self',{}).get('HostName','flywheel1'))" 2>/dev/null || true)

echo
echo "GCompris WASM PWA is live:"
if [[ -n "$TAILNET" && -n "$TS_HOST" ]]; then
  echo "  https://${TS_HOST}.${TAILNET}/"
fi
echo "  http://127.0.0.1:${LOCAL_PORT}/   (local fallback)"
echo
echo "Press Ctrl+C to stop and remove the tailscale serve rule."
echo

wait "$PYTHON_PID"
