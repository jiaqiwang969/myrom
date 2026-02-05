#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SSH_PASS="${SSH_PASS:-alpine}"
SSH_USER="${SSH_USER:-root}"
SSH_LOCAL_PORT="${SSH_LOCAL_PORT:-2222}"
UDID="${UDID:-}"
AUTO_INSTALL_MYROMCTL="${AUTO_INSTALL_MYROMCTL:-1}"

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
log="logs/iproxy_verify_dt_${port}_${ts}.log"

echo "[verify] Device UDID: $UDID"
echo "[verify] Forwarding localhost:$port -> device:22 via iproxy"
echo "[verify] iproxy log: $log"

iproxy -u "$UDID" "${port}:22" >"$log" 2>&1 &
iproxy_pid=$!
trap "kill $iproxy_pid 2>/dev/null || true" EXIT

sleep 1

run_ssh() {
  sshpass -p "$SSH_PASS" ssh \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=3 \
    -p "$port" "${SSH_USER}@localhost" "$@"
}

if [[ "$AUTO_INSTALL_MYROMCTL" == "1" ]]; then
  set +e
  run_ssh "test -x /usr/local/bin/myromctl" >/dev/null 2>&1
  have_myromctl=$?
  set -e

  if [[ $have_myromctl -ne 0 ]]; then
    if command -v xcrun >/dev/null 2>&1; then
      echo "[verify] myromctl not found on device; building + deploying it now..."
      DEVICE_PORT="$port" DEVICE_USER="$SSH_USER" DEVICE_PASS="$SSH_PASS" \
        ios/myromctl/build_and_deploy.sh >/dev/null
    else
      echo "[verify] WARN: xcrun not found; can't auto-install myromctl. Install it manually:" >&2
      echo "  DEVICE_PORT=$port ios/myromctl/build_and_deploy.sh" >&2
    fi
  fi
fi

manifest=""
last_err=""
for _ in $(seq 1 60); do
  set +e
  out="$(run_ssh "/usr/local/bin/myromctl" "print" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 && -n "$out" ]]; then
    manifest="$out"
    break
  fi

  last_err="$out"
  sleep 1
done

if [[ -z "$manifest" ]]; then
  echo "[verify] WARN: failed to read IODeviceTree:/chosen myrom-manifest via myromctl." >&2
  echo "[verify] last ssh output:" >&2
  echo "$last_err" >&2
  echo "" >&2
  echo "[verify] If myromctl is not installed yet, run once:" >&2
  echo "  DEVICE_PORT=$port ios/myromctl/build_and_deploy.sh" >&2
  echo "" >&2
  echo "[verify] Fallback: myrom fields from kern.bootargs (if any):" >&2
  run_ssh "sysctl -n kern.bootargs | tr ' ' '\\n' | egrep '^myrom(=|_)' || true" || true
  exit 2
fi

echo "[verify] myrom-manifest (from IODeviceTree:/chosen):"
echo "$manifest"
