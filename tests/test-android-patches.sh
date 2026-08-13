#!/usr/bin/env bash
# Verifies the SunPad Android runtime patches (0002) against the pinned
# upstream revisions.
#
# Offline mode (default, CI-safe): structural checks plus, when a prepared
# ref/ checkout exists, verification that the 0002 patches are applied.
#
# Network mode (SUNPAD_NETWORK_TESTS=1): shallow-clones both pinned trees and
# applies 0001 + 0002 from scratch, proving the snapshots reproduce.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG_REV=048c426ba3db0369e40826d22ad3adcce7fe7c58
DOLPHIN_REV=e13ab348f13cd67879f6db6e9d7185410f8f62c6
MG_PATCH="$ROOT/patches/ModernGekko/0002-sunpad-android-runtime.patch"
DOLPHIN_PATCH="$ROOT/patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch"

fail() { echo "android patch test: $*" >&2; exit 1; }

for patch in "$MG_PATCH" "$DOLPHIN_PATCH"; do
  [[ -s "$patch" ]] || fail "missing or empty: $patch"
done

# The 0002 ModernGekko patch must only touch the Android platform wiring.
grep -q '^diff --git a/CMakeLists.txt' "$MG_PATCH" || fail "MG patch missing CMakeLists.txt"
grep -q '^diff --git a/src/runtime/dolphin_runtime.cpp' "$MG_PATCH" || fail "MG patch missing dolphin_runtime.cpp"
grep -q 'MODERNGEKKO_HAVE_ANDROID' "$MG_PATCH" || fail "MG patch missing Android guard"
grep -q 'MAIN_CPU_THREAD, true' "$MG_PATCH" || fail "MG patch missing Android dual-core"
grep -q 'GFX_HACK_VI_SKIP, true' "$MG_PATCH" || fail "MG patch missing Android VI skip"
grep -q 'VertexLoaderType::Native' "$MG_PATCH" || fail "MG patch missing Android native vertex loader"
grep -q 'AsynchronousSkipRendering' "$MG_PATCH" || fail "MG patch missing Android async-skip shaders"

# The Dolphin 0002 patch must add the Android platform and decouple OpenSL ES.
grep -q '^diff --git a/Source/Core/DolphinNoGUI/PlatformAndroid.cpp' "$DOLPHIN_PATCH" \
  || fail "dolphin patch missing PlatformAndroid.cpp"
grep -q '^diff --git a/Source/Core/AudioCommon/OpenSLESStream.cpp' "$DOLPHIN_PATCH" \
  || fail "dolphin patch missing OpenSLESStream.cpp"
grep -q 'SunPadAndroidSetJavaVM' "$DOLPHIN_PATCH" || fail "dolphin patch missing SunPad Android audio wiring"
grep -q 'SunPadAndroidQueryAudio' "$DOLPHIN_PATCH" || fail "dolphin patch missing cached AudioUtils query"
grep -q 'CreateAndroidPlatform' "$DOLPHIN_PATCH" || fail "dolphin patch missing CreateAndroidPlatform"
grep -q 'JitArm64' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android JitArm64 exclusion"
grep -q 'WorkQueueThread.h' "$DOLPHIN_PATCH" || fail "dolphin patch missing AsyncWorkThread bad_function_call fix"
grep -q 'callback.second' "$DOLPHIN_PATCH" || fail "dolphin patch missing empty config-callback guard"
grep -q 'NO_EXCEPTIONS' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android exceptions enable"
grep -q 'HAVE_EGL=1 (NDK libEGL)' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android HAVE_EGL force"
grep -q 'EmuThread: starting' "$DOLPHIN_PATCH" || fail "dolphin patch missing EmuThread stage logs"
grep -q 'GetSysDirectory now' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android Sys path recache"
grep -q 'Headless' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android OGL headless probe"
grep -q 's_get_val_func' "$DOLPHIN_PATCH" || fail "dolphin patch missing Android analytics callback guard"
grep -q 'extern "C" void SunPadNativeLog' "$DOLPHIN_PATCH" || fail "dolphin patch missing SunPadNativeLog declaration for Core.cpp"

# When a prepared ref/ tree exists, the 0002 patches must be fully applied
# (reverse-apply must succeed).
if [[ -d "$ROOT/ref/ModernGekko/.git" ]]; then
  git -C "$ROOT/ref/ModernGekko" apply --reverse --check "$MG_PATCH" >/dev/null 2>&1 \
    || fail "ModernGekko 0002 patch is not applied in ref/ (run bootstrap-dependencies.sh)"
fi
if [[ -d "$ROOT/ref/ModernGekko/vendor/dolphin/.git" ]]; then
  git -C "$ROOT/ref/ModernGekko/vendor/dolphin" apply --reverse --check "$DOLPHIN_PATCH" >/dev/null 2>&1 \
    || fail "dolphin 0002 patch is not applied in ref/ (run bootstrap-dependencies.sh)"
fi

if [[ "${SUNPAD_NETWORK_TESTS:-0}" != "1" ]]; then
  echo "android patch test: structure OK (set SUNPAD_NETWORK_TESTS=1 for clone-and-apply verification)"
  exit 0
fi

# Network mode: reproduce the patched trees from scratch.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch_at_rev() {
  local dir=$1 url=$2 rev=$3
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$rev"
  git -C "$dir" checkout -q FETCH_HEAD
}

echo "android patch test: cloning pinned trees (network mode)"
fetch_at_rev "$TMP/ModernGekko" https://github.com/ExpansionPak/ModernGekko.git "$MG_REV"
fetch_at_rev "$TMP/dolphin" https://github.com/ExpansionPak/RecompCore.git "$DOLPHIN_REV"

actual=$(git -C "$TMP/ModernGekko" rev-parse HEAD)
[[ "$actual" == "$MG_REV" ]] || fail "unexpected ModernGekko revision: $actual"
actual=$(git -C "$TMP/dolphin" rev-parse HEAD)
[[ "$actual" == "$DOLPHIN_REV" ]] || fail "unexpected dolphin revision: $actual"

git -C "$TMP/ModernGekko" apply "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch"
git -C "$TMP/ModernGekko" apply "$MG_PATCH"
git -C "$TMP/dolphin" apply "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch"
git -C "$TMP/dolphin" apply "$DOLPHIN_PATCH"

# Idempotence: the bootstrap's reverse-check must succeed on the patched tree.
git -C "$TMP/ModernGekko" apply --reverse --check "$MG_PATCH" >/dev/null 2>&1 \
  || fail "ModernGekko 0002 not idempotent"
git -C "$TMP/dolphin" apply --reverse --check "$DOLPHIN_PATCH" >/dev/null 2>&1 \
  || fail "dolphin 0002 not idempotent"

echo "android patch test: 0001 + 0002 apply cleanly at pinned revisions (network mode)"
