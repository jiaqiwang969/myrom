#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CHECKRA1N_BIN="${CHECKRA1N_BIN:-/Applications/checkra1n.app/Contents/MacOS/checkra1n}"

mkdir -p logs

if [[ ! -x "$CHECKRA1N_BIN" ]]; then
  echo "[jb] ERROR: checkra1n not found or not executable: $CHECKRA1N_BIN" >&2
  echo "[jb] Set CHECKRA1N_BIN=/path/to/checkra1n (inside checkra1n.app) and retry." >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
cr_log="logs/checkra1n_jb_${ts}.log"

echo "[jb] Quit checkra1n GUI if it's open (avoid USB exclusive access issues)."
echo "[jb] Starting checkra1n (normal jailbreak flow; no pongo shell)."
echo "[jb] When it says 'Waiting for DFU devices', put the phone into DFU (screen stays black)."
echo "[jb] Logging: $cr_log"

# checkra1n is x86_64; on Apple Silicon it runs via Rosetta.
if [[ "$(uname -m)" == "arm64" ]]; then
  arch -x86_64 "$CHECKRA1N_BIN" -c -v -V -n 2>&1 | tee "$cr_log"
else
  "$CHECKRA1N_BIN" -c -v -V -n 2>&1 | tee "$cr_log"
fi

echo "[jb] Done. If the phone booted jailbroken, Cydia should open (no instant crash)."
