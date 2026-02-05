#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$ROOT_DIR/build"

DEVICE_HOST="${DEVICE_HOST:-localhost}"
DEVICE_PORT="${DEVICE_PORT:-2222}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"

OUT="$WORK_DIR/myromctl"

mkdir -p "$WORK_DIR"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "[myromctl] ERROR: xcrun not found (install Xcode Command Line Tools)." >&2
  exit 1
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "[myromctl] Building: $OUT"
xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=12.0 \
  -O2 \
  -Wall -Wextra \
  "$ROOT_DIR/main.c" \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$OUT"

echo "[myromctl] Deploying to device: $DEVICE_USER@$DEVICE_HOST:$DEVICE_PORT"
sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no -P "$DEVICE_PORT" \
  "$OUT" \
  "${DEVICE_USER}@${DEVICE_HOST}:/tmp/myromctl"

sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no -p "$DEVICE_PORT" "${DEVICE_USER}@${DEVICE_HOST}" <<'EOF'
set -e
mkdir -p /usr/local/bin
mv -f /tmp/myromctl /usr/local/bin/myromctl
chown root:wheel /usr/local/bin/myromctl
chmod 0755 /usr/local/bin/myromctl

if command -v ldid >/dev/null 2>&1; then
  ldid -S /usr/local/bin/myromctl
else
  echo "[myromctl] WARN: ldid not found on device; myromctl may fail to exec on some setups." >&2
fi

echo "[myromctl] Installed: /usr/local/bin/myromctl"
/usr/local/bin/myromctl print || true
EOF

echo "[myromctl] Done."

