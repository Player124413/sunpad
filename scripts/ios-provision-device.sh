#!/usr/bin/env bash
# SunPad iOS/iPadOS provisioning for a physical device: assembles the locally
# built ModernGekko / Dolphin-derived core into one static archive the app
# links, and records the dev-only game-data + module locations. The module
# path is device-sandbox-relative (/tmp maps to the app container's tmp/).
#
# Everything referenced here is locally generated from the user's legally
# obtained GMSE01 disc and is excluded from Git. Nothing is redistributed.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
IOS_BUILD="$MG/build-ios-device"
OUT="$ROOT/apple/ios/Provisioned"
LIBS_DIR="$OUT/libs"

mkdir -p "$LIBS_DIR"

if [[ ! -d "$IOS_BUILD" ]]; then
  echo "iOS device core build missing: $IOS_BUILD (run scripts/ios-build-core-device.sh first)" >&2
  exit 1
fi

LIBS=(
  "$IOS_BUILD/libmoderngekko.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/UICommon/libuicommon.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/Core/libcore.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/DiscIO/libdiscio.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Null/libvideonull.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Metal/libvideometal.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/OGL/libvideoogl.a"
  "$IOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Software/libvideosoftware.a"
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
)

# fmt device slice comes from the vendored Externals build; lz4/zstd are not
# produced by the core build, so device slices are built separately from the
# vendored sources into /tmp/sunpad-ios-libs-device.
EXTRA=(
  "$IOS_BUILD/vendor/dolphin/Externals/fmt/fmt/libfmt.a"
  "/tmp/sunpad-ios-libs-device/liblz4.a"
  "/tmp/sunpad-ios-libs-device/libzstd.a"
)
for lib in "${EXTRA[@]}"; do
  if [[ ! -f "$lib" ]]; then
    FOUND="$(find "$IOS_BUILD/vendor/dolphin/Externals" -name "$(basename "$lib")" 2>/dev/null | head -1 || true)"
    if [[ -n "$FOUND" ]]; then
      LIBS+=("$FOUND")
    else
      echo "missing device static library: $lib" >&2
      exit 1
    fi
  else
    LIBS+=("$lib")
  fi
done

MISSING=()
for lib in "${LIBS[@]}"; do
  if [[ ! -f "$lib" ]]; then
    MISSING+=("$lib")
  fi
done
if (( ${#MISSING[@]} )); then
  printf 'missing iOS device core libraries:\n'
  printf '  %s\n' "${MISSING[@]}"
  exit 1
fi

libtool -static -o "$LIBS_DIR/libSunPadCore.a" "${LIBS[@]}"
echo "merged: $LIBS_DIR/libSunPadCore.a"

# Dev provisioning manifest. DevModulePath is sandbox-relative: inside the app
# sandbox /tmp maps to the app container's tmp/ directory. Keep the device
# filename at the root of tmp because devicectl flattens directory uploads.
# DevGameRoot is unused on a real device (the import flow prefers the extracted
# root it produces).
GAME_ROOT="$TPL/extracted/Super-Mario-Sunshine"
MODULE="/tmp/module-ios-device/gGMSE01_recomp.dylib"
cat > "$OUT/dev-config.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DevGameRoot</key>
	<string>$GAME_ROOT</string>
	<key>DevModulePath</key>
	<string>$MODULE</string>
	<key>DeviceModuleRelativePath</key>
	<string>gGMSE01_recomp.dylib</string>
</dict>
</plist>
PLIST
echo "dev config: $OUT/dev-config.plist"
