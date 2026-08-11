#!/usr/bin/env bash
# Recreates SunPad's ignored upstream source tree at exact reviewed commits and
# applies the complete Apple + Android runtime patch set. No game data is
# downloaded.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REF="$ROOT/ref"
MG="$REF/ModernGekko"
TPL="$REF/ModernGekko-Template"

MG_REV=048c426ba3db0369e40826d22ad3adcce7fe7c58
DOLPHIN_REV=e13ab348f13cd67879f6db6e9d7185410f8f62c6
TPL_REV=1ee85bb5e09c38f493a09f5fa6e9dc8228b23e42

mkdir -p "$REF"

ensure_checkout() {
  local url=$1 path=$2 revision=$3
  if [[ ! -d "$path/.git" ]]; then
    git clone "$url" "$path"
    git -C "$path" checkout --detach "$revision"
  fi

  local actual
  actual=$(git -C "$path" rev-parse HEAD)
  if [[ "$actual" != "$revision" ]]; then
    echo "unexpected revision in $path" >&2
    echo "  expected: $revision" >&2
    echo "  actual:   $actual" >&2
    echo "Move or clean that ignored checkout before bootstrapping." >&2
    exit 1
  fi
}

apply_patch_once() {
  local checkout=$1 patch=$2
  if git -C "$checkout" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "already applied: ${patch#$ROOT/}"
  elif git -C "$checkout" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$checkout" apply "$patch"
    echo "applied: ${patch#$ROOT/}"
  else
    echo "patch does not apply cleanly: $patch" >&2
    exit 1
  fi
}

verify_patch_scope() {
  local checkout=$1 patch=$2 extra_allowed=${3:-}
  local allowed changed
  allowed=$(awk '/^diff --git / {sub(/^b\//, "", $4); print $4}' "$patch")
  while IFS= read -r changed; do
    [[ -z "$changed" || "$changed" == "$extra_allowed" ]] && continue
    if ! grep -Fqx "$changed" <<<"$allowed"; then
      echo "unexpected local dependency change: $checkout/$changed" >&2
      exit 1
    fi
  done < <(git -C "$checkout" status --porcelain --untracked-files=all | sed -E 's/^.. //')
}

require_clean_checkout() {
  local checkout=$1
  if [[ -n "$(git -C "$checkout" status --porcelain --untracked-files=all)" ]]; then
    echo "unexpected local changes in $checkout" >&2
    exit 1
  fi
}

ensure_checkout https://github.com/ExpansionPak/ModernGekko.git "$MG" "$MG_REV"
ensure_checkout https://github.com/ExpansionPak/ModernGekko-Template.git "$TPL" "$TPL_REV"
require_clean_checkout "$TPL"

git -C "$MG" submodule update --init vendor/dolphin
REQUIRED_DOLPHIN_SUBMODULES=(
  DolRecomp
  Externals/SDL/SDL Externals/SFML/SFML Externals/bzip2/bzip2
  Externals/cpp-optparse/cpp-optparse Externals/cubeb/cubeb
  Externals/curl/curl Externals/enet/enet Externals/fmt/fmt
  Externals/glslang/glslang Externals/hidapi/hidapi-src
  Externals/imgui/imgui Externals/implot/implot Externals/libspng/libspng
  Externals/libusb/libusb Externals/lz4/lz4
  Externals/minizip-ng/minizip-ng Externals/pugixml/pugixml
  Externals/spirv_cross/SPIRV-Cross Externals/tinygltf/tinygltf
  Externals/watcher/watcher Externals/xxhash/xxHash
  Externals/zlib-ng/zlib-ng Externals/zstd/zstd
)
git -C "$MG/vendor/dolphin" submodule update --init "${REQUIRED_DOLPHIN_SUBMODULES[@]}"
git -C "$MG/vendor/dolphin/Externals/cubeb/cubeb" submodule update --init --recursive

actual_dolphin=$(git -C "$MG/vendor/dolphin" rev-parse HEAD)
if [[ "$actual_dolphin" != "$DOLPHIN_REV" ]]; then
  echo "unexpected ModernGekko vendor/dolphin revision: $actual_dolphin" >&2
  exit 1
fi

apply_patch_once "$MG" "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch"
apply_patch_once "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch"
verify_patch_scope "$MG" \
  "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch" vendor/dolphin
verify_patch_scope "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch"

# Android runtime deltas (0002): ANativeWindow platform, SunPad OpenSL ES
# audio wiring, and the Pipes-only input stance. libadrenotools is only
# needed for Android arm64 Vulkan builds, so it is initialized only when an
# Android NDK is available on this machine.
if [[ -n "${ANDROID_NDK_HOME:-}${ANDROID_NDK_ROOT:-}" ]]; then
  git -C "$MG/vendor/dolphin" submodule update --init Externals/libadrenotools
fi
apply_patch_once "$MG" "$ROOT/patches/ModernGekko/0002-sunpad-android-runtime.patch"
apply_patch_once "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch"
verify_patch_scope "$MG" \
  "$ROOT/patches/ModernGekko/0002-sunpad-android-runtime.patch" vendor/dolphin
verify_patch_scope "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch"

echo "SunPad dependencies are pinned and patched."
