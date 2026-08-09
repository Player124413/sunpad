#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TPL="$ROOT/ref/ModernGekko-Template"
PORT="$ROOT/ref/ModernGekko/build-desktop-tools-public/moderngekko-port"
GAME="$TPL/extracted/Super-Mario-Sunshine"
OUT="$TPL/build/modules-macos14"
LOGDIR="$ROOT/artifacts/runtime"
mkdir -p "$LOGDIR"
if [[ ! -x "$PORT" ]]; then
  echo "moderngekko-port missing; build tools first" >&2
  exit 1
fi
if [[ ! -f "$GAME/sys/main.dol" ]]; then
  echo "extracted game missing" >&2
  exit 1
fi
STAMP=$(date +%Y-%m-%d-%H%M%S)
LOG="$LOGDIR/${STAMP}-stage1-run.log"
echo "Launching GMSE01 via moderngekko-port run; log=$LOG"
# Prefer Metal when available
set +e
"$PORT" run "$GAME" --backend c --toolchain clang --output "$OUT" -- --graphics Metal 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
echo "exit=$rc" | tee -a "$LOG"
exit "$rc"
