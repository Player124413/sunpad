#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ISO="$ROOT/ref/Super Mario Sunshine.iso"
TPL="$ROOT/ref/ModernGekko-Template"
echo "SunPad Stage 1 status"
echo "repo: $ROOT"
if [[ -f "$ISO" ]]; then
  file "$ISO"
else
  echo "ISO missing: $ISO"
fi
for b in dolrecomp moderngekko-port moderngekko-run; do
  p="$TPL/lib/ModernGekko/build/$b"
  if [[ -x "$p" ]]; then
    file "$p"
  else
    echo "missing tool: $p"
  fi
done
if [[ -f "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" ]]; then
  echo "extracted main.dol present"
else
  echo "extracted main.dol missing"
fi
if [[ -d "$TPL/extracted/Super-Mario-Sunshine/recomp/generated/chunks" ]]; then
  echo "recomp chunks: $(ls "$TPL/extracted/Super-Mario-Sunshine/recomp/generated/chunks" | wc -l | tr -d ' ')"
fi
mod=$(find "$TPL/build/modules" -name 'gGMSE01_recomp.dylib' 2>/dev/null | head -1 || true)
if [[ -n "${mod:-}" ]]; then
  echo "module: $mod"
  file "$mod"
else
  echo "module dylib not built yet"
fi
