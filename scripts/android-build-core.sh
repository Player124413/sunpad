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
  # Force the 64-bit ABI through the -D channel as well (belt and braces:
  # the NDK toolchain defaults to armeabi-v7a, which Dolphin rejects).
  -DANDROID_ABI=arm64-v8a
  -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a
  -DCMAKE_SYSTEM_PROCESSOR=aarch64
  -DANDROID_PLATFORM=android-26
  -DANDROID_STL=c++_shared
  # SunPad hosts the runtime with its own JNI layer; Dolphin's Android app
  # JNI target ("main", copies Data/Sys via CMAKE_SOURCE_DIR) is not built.
  -DSUNPAD_NO_DOLPHIN_ANDROID_JNI=ON
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

# Guard against the NDK toolchain silently picking the 32-bit ABI.
if ! grep -qE "CMAKE_SYSTEM_PROCESSOR:.*aarch64" "$BUILD/CMakeCache.txt"; then
  echo "configure produced a non-arm64 toolchain; aborting" >&2
  grep -E "CMAKE_(ANDROID_ARCH_ABI|SYSTEM_PROCESSOR|ANDROID_ABI)" \
    "$BUILD/CMakeCache.txt" >&2 || true
  exit 1
fi

echo "==> Building core libraries (-j$JOBS)"
ninja -C "$BUILD" libmoderngekko.a -j"$JOBS"

# Build the externals the merged archive list links explicitly. They are
# not necessarily in libmoderngekko.a's dependency graph, so their static
# archives may not exist yet (libcharset for libiconv's locale_charset,
# linkernsbypass for adrenotools).
ninja -C "$BUILD" iconv libcharset linkernsbypass adrenotools -j"$JOBS" 2>/dev/null \
  || echo "note: some externals targets not buildable in this configuration"

# ---------------------------------------------------------------------------
# Optional: GMSE01 recompiled module. SUNPAD_PREBUILT_MODULE lets CI (or a
# local caller) reuse an already-built Android arm64 module instead of doing
# the expensive source-generation/module-build pass. Without it, preserve the
# existing source-generation path from scripts/prepare-game.sh.
validate_android_module() {
  local module=$1
  [[ -s "$module" ]] || { echo "prebuilt module is missing or empty: $module" >&2; exit 1; }
  python3 - "$module" <<'PY'
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as module:
    header = module.read(20)
if len(header) < 20 or header[:4] != b"\x7fELF":
    raise SystemExit("prebuilt module is not an ELF file")
if header[4] != 2 or header[5] != 1:
    raise SystemExit("prebuilt module must be a 64-bit little-endian ELF file")
e_type, e_machine = struct.unpack_from("<HH", header, 16)
if e_type != 3 or e_machine != 183:
    raise SystemExit(
        f"prebuilt module must be an Android arm64 shared library "
        f"(type={e_type}, machine={e_machine})"
    )
PY
}

MODULE_SO=""
if [[ -n "${SUNPAD_PREBUILT_MODULE:-}" ]]; then
  MODULE_SO="$SUNPAD_PREBUILT_MODULE"
  validate_android_module "$MODULE_SO"
  echo "==> Reusing prebuilt GMSE01 Android module: $MODULE_SO"
else
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
    validate_android_module "$MODULE_SO"
  else
    echo "==> Skipping GMSE01 module build (no prepared game sources; run"
    echo "    scripts/prepare-game.sh locally, or set SUNPAD_PREBUILT_MODULE)"
  fi
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

# Archives whose exact output name/path varies across externals versions;
# locate them by filename inside the build tree.
DISCOVERED_ARCHIVES=(
  libiconv.a libvideosoftware.a libadrenotools.a libbz2.a libbz2_static.a
  # libcharset is built as part of the vendored libiconv; linkernsbypass is
  # the nested submodule of libadrenotools. Both are required by the link.
  libcharset.a liblinkernsbypass.a
)
# bzip2 may come from the system (libbz2-dev) via BZip2::BZip2 instead of a
# bundled archive; in that case nothing is discovered and libdiscio already
# links the system library.
MISSING_DISCOVERED=()
for name in "${DISCOVERED_ARCHIVES[@]}"; do
  lib="$(find "$BUILD" -name "$name" 2>/dev/null | head -1)"
  if [[ -z "$lib" ]]; then
    MISSING_DISCOVERED+=("$name")
  else
    LIBS+=("$lib")
    echo "discovered: $lib"
  fi
done
if (( ${#MISSING_DISCOVERED[@]} )); then
  echo "note: not produced by this build (may be a system library): ${MISSING_DISCOVERED[*]}" >&2
fi

# bzip2: the vendored submodule has no CMake build, and the system libbz2
# is x86_64-only (cannot link into the arm64 libsunpad.so). Compile the
# vendored sources with the NDK toolchain into a static arm64 libbz2.a.
# NDK toolchain helpers for the hand-built static libraries below.
NDK_PREBUILT="$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin)"
NDK_CC="$NDK_PREBUILT/aarch64-linux-android26-clang"
NDK_AR="$NDK_PREBUILT/llvm-ar"

# bzip2: the vendored submodule has no CMake build, and the system libbz2
# is x86_64-only (cannot link into the arm64 libsunpad.so). Compile the
# vendored sources with the NDK toolchain into a static arm64 libbz2.a.
if ! grep -q 'libbz2' <<<"${LIBS[*]}"; then
  BZ2_SRC="$ROOT/android/vendor/bzip2"
  if [[ -d "$BZ2_SRC" ]]; then
    echo "==> Building static bzip2 (arm64) with the NDK toolchain"
    BZ2_BUILD="$BUILD/bzip2-build"
    mkdir -p "$BZ2_BUILD"
    for src in blocksort huffman crctable randtable compress decompress bzlib; do
      "$NDK_CC" -c -O2 -fPIC -I"$BZ2_SRC" "$BZ2_SRC/$src.c" -o "$BZ2_BUILD/$src.o"
    done
    "$NDK_AR" rcs "$BZ2_BUILD/libbz2.a" "$BZ2_BUILD"/*.o
    LIBS+=("$BZ2_BUILD/libbz2.a")
    echo "built: $BZ2_BUILD/libbz2.a"
  else
    echo "warning: bzip2 sources not found at $BZ2_SRC; BZ2_* symbols may fail the link" >&2
  fi
fi

# libcharset: libiconv's locale_charset lives in a separate static archive
# that the core target graph does not necessarily build. Compile it from
# the vendored sources (needs the CMake-generated config.h from the build
# tree) with the NDK toolchain.
if ! grep -q 'libcharset' <<<"${LIBS[*]}"; then
  LIBC_SRC="$MG/vendor/dolphin/Externals/libiconv/libcharset"
  LIBC_CONFIG="$(find "$BUILD" -name config.h -path "*libcharset*" 2>/dev/null | head -1)"
  if [[ -d "$LIBC_SRC" && -n "$LIBC_CONFIG" ]]; then
    echo "==> Building static libcharset (arm64) with the NDK toolchain"
    LIBC_BUILD="$BUILD/libcharset-build"
    mkdir -p "$LIBC_BUILD"
    "$NDK_CC" -c -O2 -fPIC       -I"$LIBC_SRC/include" -I"$(dirname "$LIBC_CONFIG")"       "$LIBC_SRC/lib/localcharset.c" -o "$LIBC_BUILD/localcharset.o"
    "$NDK_AR" rcs "$LIBC_BUILD/libcharset.a" "$LIBC_BUILD/localcharset.o"
    LIBS+=("$LIBC_BUILD/libcharset.a")
    echo "built: $LIBC_BUILD/libcharset.a"
  else
    echo "warning: libcharset sources or generated config.h not found; locale_charset may fail the link" >&2
  fi
fi

{
  echo "# Provisioned by scripts/android-build-core.sh — do not edit."
  echo "# Paths are host-local; this file is gitignored."
  echo "set(SUNPAD_CORE_INCLUDE_DIRS"
  # fmt (and the other externals' headers) are needed by the Dolphin core
  # headers the JNI shim includes (Log.h -> fmt/format.h etc.).
  for inc in \
      "$MG/include" \
      "$MG/vendor/dolphin/Source/Core" \
      "$MG/vendor/dolphin/Source/Android" \
      "$MG/vendor/dolphin/GXRuntime/include" \
      "$MG/vendor/dolphin/Externals/fmt/fmt/include" \
      "$MG/vendor/dolphin/Externals/enet/enet/include" \
      "$MG/vendor/dolphin/Externals/mbedtls/include" \
      "$MG/vendor/dolphin/Externals/minizip-ng/minizip-ng" \
      "$MG/vendor/dolphin/Externals/Vulkan-Headers/include" \
      "$MG/vendor/dolphin/Externals/VulkanMemoryAllocator/include"; do
    if [[ -d "$inc" ]]; then
      echo "  \"$inc\""
    fi
  done
  echo ")"
  echo "set(SUNPAD_CORE_LIBS"
  for lib in "${LIBS[@]}"; do
    echo "  \"$lib\""
  done
  echo ")"
} > "$GEN_DIR/core_libs.cmake"
echo "provisioned: $GEN_DIR/core_libs.cmake (${#LIBS[@]} archives)"

# Dolphin Android ASSERT-aborts if Sys is unset. Bundle Data/Sys into the
# APK so the app can extract it to the user directory on first launch.
SYS_SRC="$MG/vendor/dolphin/Data/Sys"
SYS_DST="$ROOT/android/app/src/main/assets/dolphin-sys"
if [[ -d "$SYS_SRC" ]]; then
  mkdir -p "$SYS_DST"
  cp -a "$SYS_SRC/." "$SYS_DST/"
  echo "bundled Dolphin Sys into $SYS_DST"
else
  echo "warning: Dolphin Data/Sys not found at $SYS_SRC" >&2
fi

if [[ -n "$MODULE_SO" ]]; then
  echo "Android core, module, and provisioning complete."
  echo "Module for on-device provisioning: $MODULE_SO"
  if [[ "${SUNPAD_BUNDLE_MODULE:-0}" == "1" ]]; then
    ASSETS_DIR="$ROOT/android/app/src/main/assets/modules"
    mkdir -p "$ASSETS_DIR"
    cp "$MODULE_SO" "$ASSETS_DIR/gGMSE01_recomp.so"
    echo "Module bundled into the app: $ASSETS_DIR/gGMSE01_recomp.so"
    echo "(the app extracts it to private storage on first launch)"
  else
    echo "Push it to the device (e.g. adb push to Download/) and install it from"
    echo "the SunPad setup menu: 'Set game module'."
  fi
else
  echo "Android core and provisioning complete (module build skipped)."
fi
