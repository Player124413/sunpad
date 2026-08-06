#!/usr/bin/env bash
# SunPad iOS/iPadOS provisioning: assembles the locally built ModernGekko /
# Dolphin-derived core into one static archive the app links, and records the
# dev-only game-data + module locations.
#
# Everything referenced here is locally generated from the user's legally
# obtained GMSE01 disc and is excluded from Git. Nothing is redistributed.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
IOS_BUILD="$MG/build-ios3"
OUT="$ROOT/apple/ios/Provisioned"
LIBS_DIR="$OUT/libs"

mkdir -p "$LIBS_DIR"

if [[ ! -d "$IOS_BUILD" ]]; then
  echo "iOS core build missing: $IOS_BUILD (run scripts/ios-build-core.sh first)" >&2
  exit 1
fi

LIBS=(
  "$IOS_BUILD/libmoderngekko.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/UICommon/libuicommon.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/Core/libcore.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/DiscIO/libdiscio.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Null/libvideonull.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Metal/libvideometal.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoCommon/libvideocommon.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/AudioCommon/libaudiocommon.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/InputCommon/libinputcommon.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/Common/libcommon.a"
  "$IOS_BUILD/vendor/dolphin/Externals/FreeSurround/libFreeSurround.a"
  "$IOS_BUILD/vendor/dolphin/Externals/SDL/SDL/libSDL3.a"
  "$IOS_BUILD/vendor/dolphin/Externals/LZO/liblzo2.a"
  "$IOS_BUILD/vendor/dolphin/Externals/spirv_cross/libspirv_cross.a"
  "$IOS_BUILD/vendor/dolphin/Externals/xxhash/libxxhash.a"
  "$IOS_BUILD/vendor/dolphin/Externals/implot/libimplot.a"
  "$IOS_BUILD/vendor/dolphin/Externals/imgui/libimgui.a"
  "$IOS_BUILD/vendor/dolphin/Externals/glslang/glslang/SPIRV/libSPIRV.a"
  "$IOS_BUILD/vendor/dolphin/Externals/glslang/glslang/glslang/libglslang.a"
  "$IOS_BUILD/vendor/dolphin/Externals/tinygltf/libtinygltf.a"
  "$IOS_BUILD/vendor/dolphin/Externals/enet/enet/libenet.a"
  "$IOS_BUILD/vendor/dolphin/Externals/SFML/libsfml-network.a"
  "$IOS_BUILD/vendor/dolphin/Externals/SFML/libsfml-system.a"
  "$IOS_BUILD/vendor/dolphin/Externals/FatFs/libFatFs.a"
  "$IOS_BUILD/vendor/dolphin/Externals/curl/curl/lib/libcurl.a"
  "$IOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedtls.a"
  "$IOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedx509.a"
  "$IOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedcrypto.a"
  "$IOS_BUILD/vendor/dolphin/Externals/libspng/libspng/libspng_static.a"
  "$IOS_BUILD/vendor/dolphin/Externals/zlib-ng/zlib-ng/libz.a"
  "$IOS_BUILD/vendor/dolphin/Externals/pugixml/pugixml/libpugixml.a"
  "$IOS_BUILD/vendor/dolphin/Externals/cpp-optparse/libcpp-optparse.a"
  "$IOS_BUILD/vendor/dolphin/Externals/minizip-ng/minizip-ng/libminizip-ng.a"
  "$IOS_BUILD/vendor/dolphin/Externals/liblzma/liblzma.a"
  "/tmp/sunpad-ios-libs2/libfmt.a"
  "/tmp/sunpad-ios-libs2/liblz4.a"
  "/tmp/sunpad-ios-libs2/libzstd.a"
)

MISSING=()
for lib in "${LIBS[@]}"; do
  if [[ ! -f "$lib" ]]; then
    MISSING+=("$lib")
  fi
done
if (( ${#MISSING[@]} )); then
  printf 'missing iOS core libraries:\n'
  printf '  %s\n' "${MISSING[@]}"
  exit 1
fi

libtool -static -o "$LIBS_DIR/libSunPadCore.a" "${LIBS[@]}"
echo "merged: $LIBS_DIR/libSunPadCore.a"

# Dev provisioning manifest (host paths; the iOS Simulator can read the host
# filesystem for acceptance testing). Replaced by the document-picker import
# flow on real devices.
GAME_ROOT="$TPL/extracted/Super-Mario-Sunshine"
MODULE="/tmp/module-ios2/gGMSE01_recomp.dylib"
cat > "$OUT/dev-config.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DevGameRoot</key>
	<string>$GAME_ROOT</string>
	<key>DevModulePath</key>
	<string>$MODULE</string>
</dict>
</plist>
PLIST
echo "dev config: $OUT/dev-config.plist"
