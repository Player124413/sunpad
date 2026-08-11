#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$(mktemp "${TMPDIR:-/tmp}/sunpad-60fps-config.XXXXXX")"
trap 'rm -f "$test_binary"' EXIT

clang++ \
  -std=c++23 \
  -I "$repo_root/ref/ModernGekko/include" \
  "$repo_root/tests/SunPadExperimental60FPSConfigTests.cpp" \
  -o "$test_binary"
"$test_binary"

grep -Fq -- '-sunpadExperimental60FPS' \
  "$repo_root/apple/ios/SunPadCoreHost.mm"
grep -Fq -- 'impl->metadata.disc_id != "GMSE01"' \
  "$repo_root/ref/ModernGekko/src/runtime/dolphin_runtime.cpp"
grep -Fq -- 'Config::SetBase(Config::MAIN_ENABLE_CHEATS, true);' \
  "$repo_root/ref/ModernGekko/src/runtime/dolphin_runtime.cpp"
grep -Fq -- 'Config::SetBase(Config::SESSION_CODE_SYNC_OVERRIDE, true);' \
  "$repo_root/ref/ModernGekko/src/runtime/dolphin_runtime.cpp"
grep -Fq -- '$60FPS [gamemasterplc]' \
  "$repo_root/ref/ModernGekko/vendor/dolphin/Data/Sys/GameSettings/GMSE01.ini"

echo "Experimental 60 FPS configuration checks passed"
