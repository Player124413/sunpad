#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$(mktemp /tmp/sunpad-controller-mapping-test.XXXXXX)"
trap 'rm -f "$OUT"' EXIT

xcrun clang++ -std=c++20 -fobjc-arc -framework Foundation \
  -I"$ROOT/apple/shared" \
  "$ROOT/tests/SunPadControllerMappingTests.mm" \
  "$ROOT/apple/shared/SunPadControllerMapping.mm" \
  -o "$OUT"
"$OUT"
