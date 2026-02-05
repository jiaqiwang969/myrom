#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$ROOT_DIR/build"

DEVICE_HOST="${DEVICE_HOST:-localhost}"
DEVICE_PORT="${DEVICE_PORT:-2222}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"

OUT_NAME="HelloSubstrate"
DYLIB="$WORK_DIR/${OUT_NAME}.dylib"

mkdir -p "$WORK_DIR"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

# Pull the Substrate header and a linkable lib from the device (keeps the project self-contained).
DEPS_DIR="$ROOT_DIR/../../deps/ios/substrate"
if [[ ! -f "$DEPS_DIR/substrate.h" || ! -f "$DEPS_DIR/libsubstrate.dylib" ]]; then
  echo "[*] Missing deps in $DEPS_DIR; run from repo root where deps/ios/substrate exists." >&2
  exit 1
fi

THIN_SUBSTRATE="$DEPS_DIR/libsubstrate_arm64.dylib"
if [[ ! -f "$THIN_SUBSTRATE" ]]; then
  # Newer ld can be picky about old-style arm64e slices; linking a thin arm64 slice is the most robust.
  lipo -thin arm64 "$DEPS_DIR/libsubstrate.dylib" -output "$THIN_SUBSTRATE"
fi

echo "[*] Building $DYLIB"
xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=12.0 \
  -fobjc-arc \
  -O2 \
  -Wall -Wextra \
  -I"$DEPS_DIR" \
  "$ROOT_DIR/Tweak.m" \
  -dynamiclib \
  "$THIN_SUBSTRATE" \
  -framework Foundation \
  -framework UIKit \
  -o "$DYLIB"

echo "[*] Deploying to device: $DEVICE_USER@$DEVICE_HOST:$DEVICE_PORT"
sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no -P "$DEVICE_PORT" \
  "$DYLIB" "$ROOT_DIR/${OUT_NAME}.plist" \
  "${DEVICE_USER}@${DEVICE_HOST}:/tmp/"

sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no -p "$DEVICE_PORT" "${DEVICE_USER}@${DEVICE_HOST}" <<'EOF'
set -e
mkdir -p /Library/MobileSubstrate/DynamicLibraries
chmod 0755 /Library/MobileSubstrate/DynamicLibraries
mv -f /tmp/HelloSubstrate.dylib /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib
mv -f /tmp/HelloSubstrate.plist /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.plist
chown root:wheel /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.plist
chmod 0755 /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib
chmod 0644 /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.plist

# Ad-hoc sign so iOS will load it.
ldid -S /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib

echo "[*] Respring (SpringBoard restart)"
killall SpringBoard || true
sleep 2

echo "[*] Verification log tail:"
tail -n 50 /var/tmp/hello_substrate_springboard.log 2>/dev/null || echo "(log not found yet)"
EOF

echo "[*] Done."
