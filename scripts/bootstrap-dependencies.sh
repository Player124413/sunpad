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
  # Idempotent application. "Already applied" is detected by a signature
  # marker (a file the patch adds, or a string it introduces), NOT by
  # `git apply --reverse --check`: later snapshots (0002) edit the same
  # files at overlapping hunks (e.g. ModernGekko/CMakeLists.txt), which
  # breaks reverse-checking of earlier patches (0001) on an 0001+0002 tree.
  local checkout=$1 patch=$2 marker=$3
  local applied=0
  if [[ "$marker" == *"::"* ]]; then
    local marker_file="${marker%%::*}" marker_regex="${marker#*::}"
    if grep -qE "$marker_regex" "$checkout/$marker_file" 2>/dev/null; then
      applied=1
    fi
  elif [[ -f "$checkout/$marker" ]]; then
    applied=1
  fi
  if (( applied )); then
    echo "already applied: ${patch#$ROOT/}"
    return
  fi
  if git -C "$checkout" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$checkout" apply "$patch"
    echo "applied: ${patch#$ROOT/}"
  else
    echo "patch does not apply cleanly: $patch" >&2
    git -C "$checkout" apply --check --verbose "$patch" >&2 || true
    exit 1
  fi
}

verify_patch_scope() {
  # Checks that every locally changed file in the checkout is covered by the
  # given patches (all of them together — later snapshots build on earlier
  # ones, so files touched by 0001 must be allowed when verifying 0002).
  # Usage: verify_patch_scope <checkout> [--allow <path>] <patch>...
  local checkout=$1
  shift
  local extra_allowed=""
  local patches=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow) extra_allowed=$2; shift 2 ;;
      *) patches+=("$1"); shift ;;
    esac
  done
  if (( ${#patches[@]} == 0 )); then
    echo "verify_patch_scope: no patches given for $checkout" >&2
    exit 1
  fi
  local allowed=""
  local patch
  for patch in "${patches[@]}"; do
    allowed="$allowed
$(awk '/^diff --git / {sub(/^b\//, "", $4); print $4}' "$patch")"
  done
  local changed
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

# Initialize ALL of the vendored Dolphin submodules recursively. A curated
# allow-list proved fragile: Dolphin's CMake references submodules outside
# the list (cpp-ipc, expr, ...), and a missing one aborts the configure
# ("does not contain a CMakeLists.txt"). Everything not built is disabled
# by the CMake flags, so the extra checkouts are harmless.
git -C "$MG/vendor/dolphin" submodule update --init --recursive

# libadrenotools (Qualcomm custom-driver support) has its own nested
# submodule lib/linkernsbypass; without it the archive builds with missing
# symbols. Ensure it is checked out even when the recursive pass above
# skipped it.
git -C "$MG/vendor/dolphin/Externals/libadrenotools" \
  submodule update --init --recursive 2>/dev/null || true

actual_dolphin=$(git -C "$MG/vendor/dolphin" rev-parse HEAD)
if [[ "$actual_dolphin" != "$DOLPHIN_REV" ]]; then
  echo "unexpected ModernGekko vendor/dolphin revision: $actual_dolphin" >&2
  exit 1
fi

apply_patch_once "$MG" "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch" \
  "CMakeLists.txt::MODERNGEKKO_HAVE_IOS"
apply_patch_once "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch" \
  "Source/Core/DolphinNoGUI/PlatformIOS.mm"

# Android runtime deltas (0002): ANativeWindow platform, SunPad OpenSL ES
# audio wiring, and the Pipes-only input stance. The Vulkan backend's
# submodules (Vulkan-Headers, VulkanMemoryAllocator, libadrenotools) are
# already initialized by the recursive update above.
apply_patch_once "$MG" "$ROOT/patches/ModernGekko/0002-sunpad-android-runtime.patch" \
  "CMakeLists.txt::MODERNGEKKO_HAVE_ANDROID"
apply_patch_once "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch" \
  "Source/Core/DolphinNoGUI/PlatformAndroid.cpp"

verify_patch_scope "$MG" --allow vendor/dolphin \
  "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch" \
  "$ROOT/patches/ModernGekko/0002-sunpad-android-runtime.patch"
verify_patch_scope "$MG/vendor/dolphin" \
  "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch" \
  "$ROOT/patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch"

echo "SunPad dependencies are pinned and patched."
