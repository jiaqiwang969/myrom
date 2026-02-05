#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SSH_PASS="${SSH_PASS:-alpine}"
SSH_USER="${SSH_USER:-root}"
SSH_LOCAL_PORT="${SSH_LOCAL_PORT:-2222}"
UDID="${UDID:-}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[verify] ERROR: missing required command: $1" >&2
    exit 1
  fi
}

require idevice_id
require iproxy
require sshpass
require lsof

if [[ -z "$UDID" ]]; then
  UDID="$(idevice_id -l 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$UDID" ]]; then
  echo "[verify] ERROR: no device UDID found via idevice_id." >&2
  echo "[verify] Unlock the phone and tap Trust if prompted, then retry." >&2
  exit 1
fi

port="$SSH_LOCAL_PORT"
for _ in $(seq 1 40); do
  if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  port=$((port + 1))
done

mkdir -p logs
ts="$(date +%Y%m%d_%H%M%S)"
log="logs/iproxy_verify_${port}_${ts}.log"

echo "[verify] Device UDID: $UDID"
echo "[verify] Forwarding localhost:$port -> device:22 via iproxy"
echo "[verify] iproxy log: $log"

iproxy -u "$UDID" "${port}:22" >"$log" 2>&1 &
iproxy_pid=$!
trap "kill $iproxy_pid 2>/dev/null || true" EXIT

sleep 1

bootargs=""
last_err=""
for _ in $(seq 1 60); do
  set +e
  out="$(sshpass -p "$SSH_PASS" ssh \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=3 \
    -p "$port" "${SSH_USER}@localhost" \
    "sysctl -n kern.bootargs" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 && -n "$out" ]]; then
    bootargs="$out"
    break
  fi

  last_err="$out"
  sleep 1
done

if [[ -z "$bootargs" ]]; then
  echo "[verify] ERROR: SSH failed." >&2
  echo "[verify] last ssh output:" >&2
  echo "$last_err" >&2
  echo "[verify] If you haven't installed OpenSSH on the phone yet, install it in Cydia and retry." >&2
  exit 2
fi

echo "[verify] myrom fields (from kern.bootargs):"
echo "$bootargs" | tr " " "\n" | egrep "^myrom(=|_)" || echo "(none)"

