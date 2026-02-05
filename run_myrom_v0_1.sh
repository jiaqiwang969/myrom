#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CHECKRA1N_BIN="${CHECKRA1N_BIN:-/Applications/checkra1n.app/Contents/MacOS/checkra1n}"
PONGOTERM_BIN="${PONGOTERM_BIN:-checkra1n_research/pongoOS/scripts/pongoterm}"
MODULE_DIR="${MODULE_DIR:-modules/myrom_manifest}"
MODULE_BIN="${MODULE_BIN:-${MODULE_DIR}/build/myrom_manifest}"

SSH_PASS="${SSH_PASS:-alpine}"
SSH_USER="${SSH_USER:-root}"
SSH_LOCAL_PORT="${SSH_LOCAL_PORT:-2222}"

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
cr_log="logs/checkra1n_pongo_${ts}.log"
pt_log="logs/pongoterm_myrom_${ts}.log"
verify_log="logs/verify_myrom_${ts}.log"

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
  echo "[myrom] WARN: device did not appear in normal mode within 120s; skipping SSH verification." | tee "$verify_log"
  echo "[myrom] Next: once iOS boots, run: sysctl -n kern.bootargs" | tee -a "$verify_log"
  exit 0
fi

echo "[myrom] Device UDID: $udid"

# Pick a local port (avoid collisions with an already-running iproxy).
port="$SSH_LOCAL_PORT"
for _ in $(seq 1 20); do
  if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  port=$((port + 1))
done

iproxy -u "$udid" "${port}:22" >"logs/iproxy_${port}_${ts}.log" 2>&1 &
iproxy_pid="$!"
trap 'kill "$iproxy_pid" 2>/dev/null || true' EXIT

echo "[myrom] Verifying boot-args over SSH (local port $port)..." | tee "$verify_log"
for _ in $(seq 1 120); do
  if sshpass -p "$SSH_PASS" ssh \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 \
      -p "$port" "${SSH_USER}@localhost" \
      "sysctl -n kern.bootargs | tr ' ' '\\n' | egrep '^myrom' || true" \
      2>&1 | tee -a "$verify_log" | rg -q "^(myrom=|myrom_)" ; then
    echo "[myrom] OK: myrom fields found in kern.bootargs." | tee -a "$verify_log"
    exit 0
  fi
  sleep 1
done

echo "[myrom] WARN: SSH verification timed out (is SSH installed/running on the phone?)." | tee -a "$verify_log"
echo "[myrom] You can verify on-device as root: sysctl -n kern.bootargs" | tee -a "$verify_log"
