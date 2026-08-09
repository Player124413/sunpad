#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/home"

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation \
  -I"$ROOT/apple/shared" \
  "$ROOT/apple/shared/SunPadDiagnostics.mm" \
  "$ROOT/tests/SunPadDiagnosticsTests.mm" \
  -o "$TEMP_DIR/SunPadDiagnosticsTests"

CFFIXED_USER_HOME="$TEMP_DIR/home" "$TEMP_DIR/SunPadDiagnosticsTests"
