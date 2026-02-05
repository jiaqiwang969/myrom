#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CHECKRA1N_BIN="${CHECKRA1N_BIN:-/Applications/checkra1n.app/Contents/MacOS/checkra1n}"
PONGOTERM_BIN="${PONGOTERM_BIN:-checkra1n_research/pongoOS/scripts/pongoterm}"

mkdir -p logs

if [[ ! -x "$CHECKRA1N_BIN" ]]; then
  echo "[pongo] ERROR: checkra1n not found or not executable: $CHECKRA1N_BIN" >&2
  echo "[pongo] Set CHECKRA1N_BIN=/path/to/checkra1n (inside checkra1n.app) and retry." >&2
  exit 1
fi

if [[ ! -x "$PONGOTERM_BIN" ]]; then
  echo "[pongo] Building pongoterm..."
  make -C checkra1n_research/pongoOS/scripts pongoterm >/dev/null
fi

ts="$(date +%Y%m%d_%H%M%S)"
cr_log="logs/checkra1n_pongo_${ts}.log"

echo "[pongo] If checkra1n GUI is open, quit it first (avoid USB exclusive access issues)."
echo "[pongo] Starting checkra1n in pongo shell mode (-p) with early exit (-E)."
echo "[pongo] When it says 'Waiting for DFU devices', put the phone into DFU (screen stays black)."
echo "[pongo] Logging: $cr_log"

# checkra1n is x86_64; on Apple Silicon it runs via Rosetta.
if [[ "$(uname -m)" == "arm64" ]]; then
  arch -x86_64 "$CHECKRA1N_BIN" -c -p -E -v -V -n 2>&1 | tee "$cr_log"
else
  "$CHECKRA1N_BIN" -c -p -E -v -V -n 2>&1 | tee "$cr_log"
fi

echo "[pongo] checkra1n exited; connecting to pongoOS..."
echo "[pongo] Tip: don't run 'bootx' unless you want to continue booting iOS."
exec "$PONGOTERM_BIN"

