#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IPA="${1:?usage: scripts/audit-ios-package.sh <SunPad.ipa>}"
[[ "$IPA" = /* ]] || IPA="$ROOT/$IPA"

fail() {
  echo "iOS package audit failed: $*" >&2
  exit 1
}

[[ -f "$IPA" ]] || fail "IPA not found: $IPA"
unzip -tq "$IPA" >/dev/null || fail "ZIP integrity check failed"

entries="$(unzip -Z1 "$IPA")"
grep -Fxq 'Payload/SunPad.app/SunPad' <<<"$entries" ||
  fail "app executable is missing"
grep -Fxq 'Payload/SunPad.app/gGMSE01_recomp.dylib' <<<"$entries" ||
  fail "GMSE01 module is missing"
grep -Fxq 'Payload/SunPad.app/LICENSE' <<<"$entries" ||
  fail "GPL license is missing"
grep -Fxq 'Payload/SunPad.app/THIRD_PARTY_NOTICES.md' <<<"$entries" ||
  fail "third-party notices are missing"
if grep -Eq '(^|/)\.\.(/|$)|^/|(^|/)__MACOSX(/|$)' <<<"$entries"; then
  fail "archive contains an unsafe path"
fi
if grep -Eiq '\.(iso|gcm|rvz|wia|wbfs|gcz|gci|sav|raw|log|mobileprovision|p12|p8|pem|key|cer)$|(^|/)_CodeSignature(/|$)' <<<"$entries"; then
  fail "archive contains game data, a save, a log, or signing material"
fi

extract_root="$(mktemp -d /tmp/sunpad-ipa-audit.XXXXXX)"
trap 'rm -rf "$extract_root"' EXIT
unzip -q "$IPA" -d "$extract_root"
app="$extract_root/Payload/SunPad.app"
executable="$app/SunPad"
module="$app/gGMSE01_recomp.dylib"

[[ "$(find "$extract_root/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = 1 ]] ||
  fail "IPA must contain exactly one app"
[[ "$(lipo -archs "$executable")" = arm64 ]] || fail "app is not arm64-only"
[[ "$(lipo -archs "$module")" = arm64 ]] || fail "module is not arm64-only"
vtool -show-build "$executable" | grep -Eq 'platform +IOS$' || fail "app is not an iPhoneOS product"
vtool -show-build "$module" | grep -Eq 'platform +IOS$' || fail "module is not an iPhoneOS product"
vtool -show-build "$executable" | grep -Eq 'minos +16\.0$' || fail "app minimum OS is not iOS 16.0"
vtool -show-build "$module" | grep -Eq 'minos +16\.0$' || fail "module minimum OS is not iOS 16.0"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = com.sunpad.SunPad ]] ||
  fail "unexpected bundle identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" = 0.1.0 ]] ||
  fail "unexpected app version"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")" = 16.0 ]] ||
  fail "Info.plist minimum OS is not iOS 16.0"
[[ ! -d "$app/_CodeSignature" && ! -f "$app/embedded.mobileprovision" ]] ||
  fail "unsigned package contains signing material"
codesign --verify --strict "$app" >/dev/null 2>&1 && fail "app is still signed"
codesign --verify --strict "$module" >/dev/null 2>&1 && fail "module is still signed"

for file in "$executable" "$module" "$app/dev-config.plist"; do
  [[ -e "$file" ]] || continue
  if LC_ALL=C strings -a "$file" | grep -E '/Users/|/Volumes/|github_pat_|gh[pousr]_|AKIA[0-9A-Z]{16}' >/dev/null; then
    fail "package contains a personal path or likely credential: $file"
  fi
done

echo "iOS package audit passed: $IPA"
