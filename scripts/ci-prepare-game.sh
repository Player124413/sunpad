#!/usr/bin/env bash
# Linux-compatible variant of scripts/prepare-game.sh for GitHub Actions:
# validates the user-supplied GMSE01 image, extracts it with dolrecomp, and
# generates the DolRecomp C sources the Android module build consumes.
#
# The generated sources are written to the same host path the Apple
# prepare-game.sh uses (ref/ModernGekko-Template/build/modules-macos14), so
# scripts/android-build-core.sh picks them up unchanged.
#
# Only the desktop generation tools are built (no emulator runner), with
# SDL/cubeb/upnp disabled so the toolchain needs just cmake, ninja,
# pkg-config, clang, python3, git.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISO=${1:-}
EXPECTED_SHA256=67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d

if [[ -z "$ISO" || ! -f "$ISO" ]]; then
  echo "usage: $0 /path/to/GMSE01.iso" >&2
  exit 2
fi
ISO="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha=$(sha256sum "$ISO" | awk '{print $1}')
else
  actual_sha=$(shasum -a 256 "$ISO" | awk '{print $1}')
fi
if [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
  echo "unsupported disc image SHA-256: $actual_sha" >&2
  echo "SunPad currently supports GMSE01 USA revision 0 only." >&2
  exit 1
fi

"$ROOT/scripts/bootstrap-dependencies.sh"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
GAME="$TPL/extracted/Super-Mario-Sunshine"
MODULES="$TPL/build/modules-macos14"
DESKTOP_BUILD="$MG/build-desktop-tools-ci"

cmake -S "$MG" -B "$DESKTOP_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_SYSTEM_LIBS=OFF \
  -DENABLE_VULKAN=OFF -DENABLE_QT=OFF -DENABLE_TESTS=OFF \
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF \
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF \
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF \
  -DENABLE_CUBEB=OFF
# NOTE: ENABLE_SDL stays ON (the default): ModernGekko's frontend targets
# (moderngekko-run/launcher/port) require an SDL3 target at configure time,
# so the vendored SDL3 submodule is configured (and built as a dependency
# of inputcommon).

echo "==> Building desktop generation tools"
cmake --build "$DESKTOP_BUILD" --target moderngekko-port \
  -j"${SUNPAD_JOBS:-$(nproc 2>/dev/null || echo 4)}"

if [[ -e "$GAME" ]]; then
  echo "existing extraction present: $GAME (reusing; run locally to regenerate)" >&2
else
  STAGING="$GAME.importing.$$"
  trap 'rm -rf "$STAGING"' EXIT
  "$DESKTOP_BUILD/dolrecomp" extract "$ISO" "$STAGING"
  test -f "$STAGING/sys/boot.bin"
  test -f "$STAGING/sys/main.dol"
  test "$(find "$STAGING/files" -type f | wc -l | tr -d ' ')" = 174
  printf '%s\n' "$EXPECTED_SHA256" > "$STAGING/.sunpad-source-sha256"
  mv "$STAGING" "$GAME"
  trap - EXIT
fi
test -f "$GAME/sys/boot.bin"
test -f "$GAME/sys/main.dol"
test -d "$GAME/files"
test "$(find "$GAME/files" -type f | wc -l | tr -d ' ')" = 174

"$DESKTOP_BUILD/moderngekko-port" build "$GAME" \
  --backend c --toolchain clang --output "$MODULES"
echo "Prepared GMSE01 generation sources at $MODULES"
