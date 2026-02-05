#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CHECKRA1N_BIN="${CHECKRA1N_BIN:-/Applications/checkra1n.app/Contents/MacOS/checkra1n}"
PONGOTERM_BIN="${PONGOTERM_BIN:-checkra1n_research/pongoOS/scripts/pongoterm}"
MODULE_DIR="${MODULE_DIR:-modules/myrom_manifest_dt}"
MODULE_BIN="${MODULE_BIN:-${MODULE_DIR}/build/myrom_manifest_dt}"

SSH_PASS="${SSH_PASS:-alpine}"
SSH_USER="${SSH_USER:-root}"
SSH_LOCAL_PORT="${SSH_LOCAL_PORT:-2222}"
AUTO_INSTALL_MYROMCTL="${AUTO_INSTALL_MYROMCTL:-1}"

mkdir -p logs

if [[ ! -x "$CHECKRA1N_BIN" ]]; then
  echo "[myrom] ERROR: checkra1n not found at: $CHECKRA1N_BIN" >&2
  echo "[myrom] Set CHECKRA1N_BIN=/path/to/checkra1n or install checkra1n.app." >&2
  exit 1
fi

echo "[myrom] Building module + tools..."
make -C "$MODULE_DIR" >/dev/null
if [[ ! -x "$PONGOTERM_BIN" ]]; then
  make -C checkra1n_research/pongoOS/scripts pongoterm >/dev/null
fi

if [[ ! -f "$MODULE_BIN" ]]; then
  echo "[myrom] ERROR: module binary not found after build: $MODULE_BIN" >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
cr_log="logs/checkra1n_pongo_v0_2_${ts}.log"
pt_log="logs/pongoterm_myrom_v0_2_${ts}.log"

echo "[myrom] Starting checkra1n (pongo shell, early-exit)."
echo "[myrom] Put the phone into DFU now (screen stays black), then wait."
echo "[myrom] Logging: $cr_log"

# NOTE: checkra1n is x86_64; on Apple Silicon it runs via Rosetta.
if [[ "$(uname -m)" == "arm64" ]]; then
  arch -x86_64 "$CHECKRA1N_BIN" -c -p -E -v -V -n 2>&1 | tee "$cr_log"
else
  "$CHECKRA1N_BIN" -c -p -E -v -V -n 2>&1 | tee "$cr_log"
fi

echo "[myrom] checkra1n exited; connecting to pongoOS and loading module (modload), then booting (bootx)."
echo "[myrom] Logging: $pt_log"
{
  echo "/send $MODULE_BIN"
  echo "modload"
  echo "sep auto"
  echo "bootx"
} | "$PONGOTERM_BIN" 2>&1 | tee "$pt_log"

echo "[myrom] Waiting for iOS to come back (usbmux)..."
udid=""
for _ in $(seq 1 120); do
  udid="$(idevice_id -l 2>/dev/null | head -n1 || true)"
  if [[ -n "$udid" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$udid" ]]; then
  echo "[myrom] WARN: device did not appear in normal mode within 120s; skipping SSH verification."
  exit 0
fi

echo "[myrom] Device UDID: $udid"
echo "[myrom] Verifying DeviceTree manifest over SSH..."

UDID="$udid" SSH_PASS="$SSH_PASS" SSH_USER="$SSH_USER" SSH_LOCAL_PORT="$SSH_LOCAL_PORT" \
  AUTO_INSTALL_MYROMCTL="$AUTO_INSTALL_MYROMCTL" ./verify_myrom_dt_manifest.sh
