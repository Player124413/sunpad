#!/usr/bin/env bash
# Guards the Android workflow's two module-input paths and its artifact output.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORKFLOW="$ROOT/ci/android-build.yml"
BUILD_SCRIPT="$ROOT/scripts/android-build-core.sh"
TOUCH_VIEW="$ROOT/android/app/src/main/java/com/sunpad/android/input/TouchControlsView.kt"
ACTIVITY="$ROOT/android/app/src/main/java/com/sunpad/android/SunPadActivity.kt"
RUNTIME_HOST="$ROOT/android/app/src/main/cpp/runtime_host.cpp"

fail() { echo "android workflow test: $*" >&2; exit 1; }

grep -q 'module_url:' "$WORKFLOW" \
  || fail "workflow missing prebuilt module_url input"
grep -q 'Reject conflicting module sources' "$WORKFLOW" \
  || fail "workflow must reject ISO and module URL together"
grep -q 'Download prebuilt GMSE01 Android module' "$WORKFLOW" \
  || fail "workflow missing prebuilt module download step"
grep -q 'SUNPAD_PREBUILT_MODULE=/tmp/gGMSE01_recomp.so' "$WORKFLOW" \
  || fail "workflow does not pass the downloaded module to the build"
grep -q 'Upload recompiled GMSE01 module' "$WORKFLOW" \
  || fail "workflow missing generated-module artifact"
grep -q 'name: gGMSE01_recomp.so' "$WORKFLOW" \
  || fail "workflow module artifact has the wrong name"

grep -q 'SUNPAD_PREBUILT_MODULE' "$BUILD_SCRIPT" \
  || fail "core build script cannot reuse a prebuilt module"
grep -q 'validate_android_module' "$BUILD_SCRIPT" \
  || fail "core build script must validate a prebuilt module"

grep -q 'ShaderCompilationMode::Synchronous' "$RUNTIME_HOST" \
  || fail "runtime host is not set to specialized shaders"
if grep -q 'ShaderCompilationMode::AsynchronousUberShaders' "$RUNTIME_HOST"; then
  fail "runtime host must not enable uber shaders"
fi

grep -q 'SetCfg(Config::MAIN_CPU_THREAD, true);' "$RUNTIME_HOST" \
  || fail "runtime host must always enable dual-core"
if grep -q -i 'dual.?core' "$ACTIVITY"; then
  fail "the Android three-dot menu must not expose a dual-core toggle"
fi
if grep -q -i 'dpad' "$TOUCH_VIEW"; then
  fail "touch overlay must not contain on-screen D-pad arrows"
fi

echo "android workflow test: module reuse, specialized shaders, and touch UI checks passed"
