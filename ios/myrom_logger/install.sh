#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"

DEVICE_HOST="${DEVICE_HOST:-localhost}"
DEVICE_PORT="${DEVICE_PORT:-2222}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"
SSH_LOCAL_PORT="${SSH_LOCAL_PORT:-2222}"
UDID="${UDID:-}"

PLIST_LOCAL="$ROOT_DIR/com.myrom.logger.plist"
PLIST_REMOTE="/Library/LaunchDaemons/com.myrom.logger.plist"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[myrom_logger] ERROR: missing required command: $1" >&2
    exit 1
  fi
}

require idevice_id
require iproxy
require sshpass
require lsof

if [[ ! -f "$PLIST_LOCAL" ]]; then
  echo "[myrom_logger] ERROR: missing plist: $PLIST_LOCAL" >&2
  exit 1
fi

if [[ -z "$UDID" ]]; then
  UDID="$(idevice_id -l 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$UDID" ]]; then
  echo "[myrom_logger] ERROR: no device UDID found via idevice_id." >&2
  echo "[myrom_logger] Unlock the phone and tap Trust if prompted, then retry." >&2
  exit 1
fi

port="$SSH_LOCAL_PORT"
for _ in $(seq 1 40); do
  if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  port=$((port + 1))
done

mkdir -p "$REPO_ROOT/logs"
ts="$(date +%Y%m%d_%H%M%S)"
log="$REPO_ROOT/logs/iproxy_install_logger_${port}_${ts}.log"

echo "[myrom_logger] Device UDID: $UDID"
echo "[myrom_logger] Forwarding localhost:$port -> device:22 via iproxy"
echo "[myrom_logger] iproxy log: $log"

iproxy -u "$UDID" "${port}:22" >"$log" 2>&1 &
iproxy_pid=$!
trap "kill $iproxy_pid 2>/dev/null || true" EXIT

DEVICE_HOST="localhost"
DEVICE_PORT="$port"

echo "[myrom_logger] Installing LaunchDaemon: $PLIST_REMOTE"
sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no -P "$DEVICE_PORT" \
  "$PLIST_LOCAL" \
  "${DEVICE_USER}@${DEVICE_HOST}:/tmp/com.myrom.logger.plist"

sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no -p "$DEVICE_PORT" "${DEVICE_USER}@${DEVICE_HOST}" <<'EOF'
set -e

if [[ ! -x /usr/local/bin/myromctl ]]; then
  echo "[myrom_logger] ERROR: /usr/local/bin/myromctl not found. Install it first (ios/myromctl/build_and_deploy.sh)." >&2
  exit 2
fi

mkdir -p /var/log/myrom
chown root:wheel /var/log/myrom
chmod 0755 /var/log/myrom

mv -f /tmp/com.myrom.logger.plist /Library/LaunchDaemons/com.myrom.logger.plist
chown root:wheel /Library/LaunchDaemons/com.myrom.logger.plist
chmod 0644 /Library/LaunchDaemons/com.myrom.logger.plist

launchctl unload /Library/LaunchDaemons/com.myrom.logger.plist 2>/dev/null || true
launchctl load /Library/LaunchDaemons/com.myrom.logger.plist
launchctl start com.myrom.logger 2>/dev/null || true

echo "[myrom_logger] OK. Latest log tail:"
tail -n 5 /var/log/myrom/myrom.jsonl 2>/dev/null || true
EOF

echo "[myrom_logger] Done."
