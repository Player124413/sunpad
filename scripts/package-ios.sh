#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="${1:-/tmp/SunPadReleaseData/Build/Products/Release-iphoneos/SunPad.app}"
MODULE="${2:-/tmp/sunpad-module-ios-device/gGMSE01_recomp.dylib}"
OUTPUT="${3:-$ROOT/artifacts/SunPad-0.1.0-preview.2-unsigned.ipa}"

[[ "$APP" = /* ]] || APP="$ROOT/$APP"
[[ "$MODULE" = /* ]] || MODULE="$ROOT/$MODULE"
[[ "$OUTPUT" = /* ]] || OUTPUT="$ROOT/$OUTPUT"
[[ -d "$APP" ]] || { echo "app not found: $APP" >&2; exit 1; }
[[ -f "$MODULE" ]] || { echo "module not found: $MODULE" >&2; exit 1; }

package_root="$(mktemp -d /tmp/sunpad-package.XXXXXX)"
trap 'rm -rf "$package_root"' EXIT
staged_app="$package_root/Payload/SunPad.app"
mkdir -p "$(dirname "$staged_app")" "$(dirname "$OUTPUT")"
ditto "$APP" "$staged_app"
ditto "$MODULE" "$staged_app/gGMSE01_recomp.dylib"

rm -rf "$staged_app/_CodeSignature"
rm -f "$staged_app/embedded.mobileprovision"
codesign --remove-signature "$staged_app/gGMSE01_recomp.dylib" 2>/dev/null || true
codesign --remove-signature "$staged_app" 2>/dev/null || true

# Keep only the device-relative module name; local host paths never belong in
# a public package.
if [[ -f "$staged_app/dev-config.plist" ]]; then
  /usr/libexec/PlistBuddy -c 'Delete :DevGameRoot' "$staged_app/dev-config.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Delete :DevModulePath' "$staged_app/dev-config.plist" 2>/dev/null || true
fi
cp "$ROOT/LICENSE" "$staged_app/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$staged_app/THIRD_PARTY_NOTICES.md"
cp "$ROOT/docs/INSTALL_IPA.md" "$staged_app/INSTALL_IPA.md"

find "$package_root" -exec touch -h -t 200001010000 {} +
temporary_ipa="$package_root/SunPad.ipa"
(
  cd "$package_root"
  find Payload \( -type f -o -type l \) -print | LC_ALL=C sort |
    zip -X -q -y "$temporary_ipa" -@
)
mv -f "$temporary_ipa" "$OUTPUT"

"$ROOT/scripts/audit-ios-package.sh" "$OUTPUT"
echo "IPA: $OUTPUT"
shasum -a 256 "$OUTPUT"
echo "This unsigned IPA must be re-signed before installation."
