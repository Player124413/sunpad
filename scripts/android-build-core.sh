#!/usr/bin/env bash
# Builds the ModernGekko / Dolphin-derived compatibility runtime for Android
# arm64-v8a and provisions the SunPad Android app: merged core archives and
# (when the locally generated game sources are present) the GMSE01
# recompiled module.
#
# Product path: ahead-of-time statically recompiled game code through the
# compatibility runtime with the Vulkan backend and OpenSL ES audio. The
# product path never enables the compiled PowerPC JIT (the static-recomp
# fallback uses the interpreter, and the software vertex loader replaces
# Dolphin's code-generating ARM64 loader).
#
# Game data is never required: the core and app provisioning work without
# it (this is what the GitHub Actions build uses). The GMSE01 module build
# step is skipped with a warning when the prepared game sources are absent;
# build the module locally with scripts/prepare-game.sh and provision it on
# the device.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
TOOLCHAIN="$ROOT/scripts/android-toolchain.cmake"
BUILD="$MG/build-android-arm64-public"
MODULE_BUILD="/tmp/sunpad-module-android"
GEN_DIR="$ROOT/android/app/src/main/cpp/generated"
JOBS="${SUNPAD_JOBS:-$(nproc 2>/dev/null || echo 8)}"

if [[ -z "${ANDROID_NDK_HOME:-}${ANDROID_NDK_ROOT:-}" ]]; then
  echo "ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) must point at the Android NDK" >&2
  exit 1
fi

"$ROOT/scripts/bootstrap-dependencies.sh"

CMAKE_COMMON=(
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
  -DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF
  -DENABLE_CUBEB=OFF -DENABLE_VULKAN=ON
  # EGL keeps the OpenGL ES backend buildable as a fallback renderer;
  # SDL defaults OFF on Android (input is Pipes-only, like the iOS app).
  -DENABLE_EGL=ON
  -DUSE_SYSTEM_LZ4=OFF -DUSE_SYSTEM_ZSTD=OFF
)

echo "==> Configuring ModernGekko core for Android arm64-v8a"
cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"

echo "==> Building core libraries (-j$JOBS)"
ninja -C "$BUILD" libmoderngekko.a -j"$JOBS"

# ---------------------------------------------------------------------------
# Optional: GMSE01 recompiled module (needs the user's locally generated
# DolRecomp sources from scripts/prepare-game.sh).
ACTIVE_FILE="$TPL/build/modules-macos14/GMSE01/active-module.txt"
if [[ -f "$ACTIVE_FILE" ]]; then
  ACTIVE_MODULE="$(<"$ACTIVE_FILE")"
  if [[ "$ACTIVE_MODULE" != /* ]]; then
    ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
  fi
  GEN="$(dirname "$ACTIVE_MODULE")/dolrecomp-output/generated"
else
  GEN="$TPL/extracted/Super-Mario-Sunshine/recomp/generated"
fi
MODULE_SO=""
if [[ -f "$GEN/generated.c" && -f "$GEN/generated.h" ]]; then
  if [[ ! -f "$GEN/main.dol" ]]; then
    cp "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" "$GEN/main.dol"
  fi
  echo "==> Building GMSE01 recompiled module for Android"
  cmake -S "$MG/vendor/dolphin/module-template" -B "$MODULE_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DGAME_ID=GMSE01 \
    -DGENERATED_DIR="$GEN" \
    -DGXRUNTIME_DIR="$MG/vendor/dolphin/GXRuntime" \
    -DCHASSIS_ABI_DIR="$MG/vendor/dolphin/Source/Core/Core/PowerPC/StaticRecomp"
  ninja -C "$MODULE_BUILD" -j"$JOBS"
  MODULE_SO="$MODULE_BUILD/gGMSE01_recomp.so"
  test -f "$MODULE_SO"
else
  echo "==> Skipping GMSE01 module build (no prepared game sources; run"
  echo "    scripts/prepare-game.sh locally and provision the module on-device)"
fi

# ---------------------------------------------------------------------------
# Provision the app: merged core archive list + include paths.
echo "==> Provisioning Android app"
mkdir -p "$GEN_DIR"

# Core-critical archives: the build fails if any of these is missing.
REQUIRED_LIBS=(
  "$BUILD/libmoderngekko.a"
  "$BUILD/vendor/dolphin/Source/Core/UICommon/libuicommon.a"
  "$BUILD/vendor/dolphin/Source/Core/Core/libcore.a"
  "$BUILD/vendor/dolphin/Source/Core/DiscIO/libdiscio.a"
  "$BUILD/vendor/dolphin/Source/Core/VideoBackends/Null/libvideonull.a"
  "$BUILD/vendor/dolphin/Source/Core/VideoBackends/Vulkan/libvideovulkan.a"
  "$BUILD/vendor/dolphin/Source/Core/VideoBackends/OGL/libvideoogl.a"
  "$BUILD/vendor/dolphin/Source/Core/VideoCommon/libvideocommon.a"
  "$BUILD/vendor/dolphin/Source/Core/AudioCommon/libaudiocommon.a"
  "$BUILD/vendor/dolphin/Source/Core/InputCommon/libinputcommon.a"
  "$BUILD/vendor/dolphin/Source/Core/Common/libcommon.a"
  "$BUILD/vendor/dolphin/Externals/FreeSurround/libFreeSurround.a"
  "$BUILD/vendor/dolphin/Externals/LZO/liblzo2.a"
  "$BUILD/vendor/dolphin/Externals/xxhash/libxxhash.a"
  "$BUILD/vendor/dolphin/Externals/glslang/glslang/SPIRV/libSPIRV.a"
  "$BUILD/vendor/dolphin/Externals/glslang/glslang/glslang/libglslang.a"
  "$BUILD/vendor/dolphin/Externals/fmt/fmt/libfmt.a"
  "$BUILD/vendor/dolphin/Externals/lz4/lz4/build/cmake/liblz4.a"
  "$BUILD/vendor/dolphin/Externals/zstd/zstd/build/cmake/lib/libzstd.a"
  "$BUILD/vendor/dolphin/Externals/libspng/libspng/libspng_static.a"
  "$BUILD/vendor/dolphin/Externals/zlib-ng/zlib-ng/libz.a"
  "$BUILD/vendor/dolphin/Externals/pugixml/pugixml/libpugixml.a"
  "$BUILD/vendor/dolphin/Externals/cpp-optparse/libcpp-optparse.a"
  "$BUILD/vendor/dolphin/Externals/tinygltf/libtinygltf.a"
  "$BUILD/vendor/dolphin/Externals/imgui/libimgui.a"
  "$BUILD/vendor/dolphin/Externals/implot/libimplot.a"
)

# Secondary archives: included when the platform build produced them
# (availability varies by host / Dolphin CMake conditions).
OPTIONAL_LIBS=(
  "$BUILD/vendor/dolphin/Externals/enet/enet/libenet.a"
  "$BUILD/vendor/dolphin/Externals/FatFs/libFatFs.a"
  "$BUILD/vendor/dolphin/Externals/curl/curl/lib/libcurl.a"
  "$BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedtls.a"
  "$BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedx509.a"
  "$BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedcrypto.a"
  "$BUILD/vendor/dolphin/Externals/minizip-ng/minizip-ng/libminizip-ng.a"
  "$BUILD/vendor/dolphin/Externals/liblzma/liblzma.a"
  "$BUILD/vendor/dolphin/Externals/SFML/libsfml-network.a"
  "$BUILD/vendor/dolphin/Externals/SFML/libsfml-system.a"
  "$BUILD/vendor/dolphin/Externals/spirv_cross/libspirv_cross.a"
)

MISSING=()
LIBS=()
for lib in "${REQUIRED_LIBS[@]}"; do
  if [[ -f "$lib" ]]; then
    LIBS+=("$lib")
  else
    MISSING+=("$lib")
  fi
done
if (( ${#MISSING[@]} )); then
  printf 'missing required Android core libraries:\n'
  printf '  %s\n' "${MISSING[@]}"
  exit 1
fi
for lib in "${OPTIONAL_LIBS[@]}"; do
  if [[ -f "$lib" ]]; then
    LIBS+=("$lib")
  else
    echo "note: optional core library not produced by this build: $lib"
  fi
done

{
  echo "# Provisioned by scripts/android-build-core.sh — do not edit."
  echo "# Paths are host-local; this file is gitignored."
  echo "set(SUNPAD_CORE_INCLUDE_DIRS"
  for inc in \
      "$MG/include" \
      "$MG/vendor/dolphin/Source/Core" \
      "$MG/vendor/dolphin/GXRuntime/include"; do
    echo "  \"$inc\""
  done
  echo ")"
  echo "set(SUNPAD_CORE_LIBS"
  for lib in "${LIBS[@]}"; do
    echo "  \"$lib\""
  done
  echo ")"
} > "$GEN_DIR/core_libs.cmake"
echo "provisioned: $GEN_DIR/core_libs.cmake (${#LIBS[@]} archives)"

if [[ -n "$MODULE_SO" ]]; then
  echo "Android core, module, and provisioning complete."
  echo "Module for on-device provisioning: $MODULE_SO"
  echo "Push it to the device (e.g. adb push to Download/) and install it from"
  echo "the SunPad setup menu: 'Set game module'."
else
  echo "Android core and provisioning complete (module build skipped)."
fi
