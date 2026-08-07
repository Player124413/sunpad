#!/usr/bin/env bash
# Builds the ModernGekko / Dolphin-derived compatibility runtime for a
# physical iOS/iPadOS device (arm64) and provisions the SunPad iOS/iPadOS app.
#
# Product path: ahead-of-time statically recompiled game code through the
# compatibility runtime. No runtime PowerPC JIT is built for iOS (the static
# recomp fallback uses the interpreter). The game module is recompiled for
# the device from the user's locally generated DolRecomp output.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
TOOLCHAIN="$ROOT/scripts/ios-device-toolchain.cmake"
BUILD="$MG/build-ios-device"

CMAKE_COMMON=(
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DCMAKE_SYSTEM_PROCESSOR=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
  -DCMAKE_BUILD_TYPE=Release
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
  -DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF
  -DENABLE_CUBEB=OFF -DENABLE_VULKAN=OFF
  # cubeb's wrapper defaults USE_SANITIZERS=ON, which needs the
  # sanitizers-cmake submodule; sanitizers are pointless with cubeb off.
  -DUSE_SANITIZERS=OFF
)

echo "==> Configuring ModernGekko core for iOS device"
cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"

echo "==> Building core libraries"
ninja -C "$BUILD" libmoderngekko.a -j8

echo "==> Building GMSE01 recompiled module for iOS device"
GEN="$TPL/extracted/Super-Mario-Sunshine/recomp/generated"
if [[ ! -f "$GEN/main.dol" ]]; then
  cp "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" "$GEN/main.dol"
fi
cmake -S "$MG/vendor/dolphin/module-template" -B /tmp/module-ios-device -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DGAME_ID=GMSE01 \
  -DGENERATED_DIR="$GEN" \
  -DGXRUNTIME_DIR="$MG/vendor/dolphin/GXRuntime" \
  -DCHASSIS_ABI_DIR="$MG/vendor/dolphin/Source/Core/Core/PowerPC/StaticRecomp"
ninja -C /tmp/module-ios-device -j8

echo "==> Provisioning app"
"$ROOT/scripts/ios-provision-device.sh"

echo "Core, module, and provisioning complete."
