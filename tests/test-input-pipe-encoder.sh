#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if command -v rg >/dev/null 2>&1; then
  SEARCH=(rg -q)
else
  SEARCH=(grep -Eq)
fi

if ! "${SEARCH[@]}" 'SunPadInputState state = \{\};' \
    "$ROOT/apple/ios/SunPadGameViewController.mm"; then
  echo "controller snapshots must be zero-initialized" >&2
  exit 1
fi

if "${SEARCH[@]}" 'SunPadInputState state;' \
    "$ROOT/apple/ios/SunPadGameViewController.mm"; then
  echo "uninitialized controller snapshot found" >&2
  exit 1
fi

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation \
  -I"$ROOT/apple/shared" \
  "$ROOT/apple/shared/SunPadInputPipeEncoder.mm" \
  "$ROOT/tests/SunPadInputPipeEncoderTests.mm" \
  -o "$TEMP_DIR/SunPadInputPipeEncoderTests"

"$TEMP_DIR/SunPadInputPipeEncoderTests"
