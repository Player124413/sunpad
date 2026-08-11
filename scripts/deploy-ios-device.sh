#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-}"
APP="${2:-/tmp/SunPadDeviceData/Build/Products/Debug-iphoneos/SunPad.app}"
MODULE="${3:-/tmp/sunpad-module-ios-device/gGMSE01_recomp.dylib}"
BUNDLE_ID="com.sunpad.SunPad"

if [[ -z "$DEVICE" ]]; then
  echo "usage: $0 <device-id> [SunPad.app] [gGMSE01_recomp.dylib]" >&2
  exit 2
fi
[[ -d "$APP" ]] || { echo "app not found: $APP" >&2; exit 1; }
[[ -f "$MODULE" ]] || { echo "module not found: $MODULE" >&2; exit 1; }

codesign --verify --deep --strict "$APP"
codesign --verify --strict "$MODULE"

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device copy to --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source "$MODULE" --destination "tmp/gGMSE01_recomp.dylib" --timeout 120
xcrun devicectl device process launch --device "$DEVICE" \
  --terminate-existing "$BUNDLE_ID"

echo "SunPad installed in place, native module provisioned, and app launched."
