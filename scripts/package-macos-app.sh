#!/usr/bin/env bash
# Builds a local Apple Silicon SunPad.app. The generated game module is copied
# only into the ignored local bundle and must never be committed or distributed.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
BUILD="${SUNPAD_MACOS_BUILD_DIR:-$MG/build-desktop}"
OUTPUT="${SUNPAD_MACOS_OUTPUT:-$ROOT/build-macos/SunPad.app}"
PATCH="$ROOT/patches/ModernGekko/0001-macos-metal-frontend.patch"

if git -C "$MG" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  : # Already applied.
elif git -C "$MG" apply --check "$PATCH" >/dev/null 2>&1; then
  git -C "$MG" apply "$PATCH"
else
  echo "ModernGekko macOS frontend patch does not apply cleanly." >&2
  exit 1
fi

cmake -S "$MG" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DMODERNGEKKO_FRONTEND_NAME=SunPad \
  -DMODERNGEKKO_LAUNCHER_OUTPUT_NAME=SunPadFrontend \
  -DMODERNGEKKO_RUNNER_OUTPUT_NAME=SunPadRunner \
  -DMODERNGEKKO_USER_DIRECTORY_NAME=SunPad \
  -DMODERNGEKKO_DEFAULT_WINDOW_TITLE=SunPad \
  -DMODERNGEKKO_LOG_FILENAME=SunPad.log \
  -DMODERNGEKKO_GAMECUBE_CONTROLLERS=ON \
  -DMODERNGEKKO_REQUIRED_DISC_ID=GMSE01 \
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
cmake --build "$BUILD" --target moderngekko-run moderngekko-launcher -j8

ACTIVE_MODULE="$(cat "$TPL/build/modules/GMSE01/active-module.txt")"
if [[ "$ACTIVE_MODULE" != /* ]]; then
  ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
fi
if [[ ! -f "$ACTIVE_MODULE" ]]; then
  echo "Generated GMSE01 desktop module not found: $ACTIVE_MODULE" >&2
  exit 1
fi

APP_PARENT="$(dirname -- "$OUTPUT")"
mkdir -p "$APP_PARENT"
if [[ -e "$OUTPUT" ]]; then
  mv "$OUTPUT" "$OUTPUT.previous.$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/apple/macos/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/apple/macos/SunPad" "$OUTPUT/Contents/MacOS/SunPad"
cp "$BUILD/SunPadFrontend" "$OUTPUT/Contents/MacOS/SunPadFrontend"
cp "$BUILD/SunPadRunner" "$OUTPUT/Contents/MacOS/SunPadRunner"
cp "$ACTIVE_MODULE" "$OUTPUT/Contents/MacOS/gGMSE01_recomp.dylib"
cp -R "$BUILD/Sys" "$OUTPUT/Contents/MacOS/Sys"
cp "$ROOT/apple/macos/default-config.ini" "$OUTPUT/Contents/Resources/default-config.ini"
cp "$ROOT/apple/macos/default-GCPadNew.ini" "$OUTPUT/Contents/Resources/default-GCPadNew.ini"
chmod +x "$OUTPUT/Contents/MacOS/SunPad"

SOURCE_ICON="$ROOT/apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
cp "$SOURCE_ICON" "$OUTPUT/Contents/Resources/AppIcon.png"

codesign --force --deep --sign - "$OUTPUT"
codesign --verify --deep --strict "$OUTPUT"
echo "$OUTPUT"
