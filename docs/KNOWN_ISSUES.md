# Known Issues

Last updated: 2026-08-06

## iOS / iPadOS

1. **Audio is silent** — cubeb is macOS-only in the vendored tree; the iOS
   build disables it. A native AVAudioSession backend is a follow-up.
2. **Module provisioning** — import/extract/boot works on-device, but the
   recompiled module is provisioned from the Mac (`dev-config.plist`); iOS has
   no C compiler, so the module for a given disc must be produced by the Mac
   toolchain and matched by game ID.
3. **Render-resolution setting not applied live** — the Native/1x-4x choice
   persists but the running runtime reads its own EFB-scale config; wiring
   `GFX_EFB_SCALE` to the live session is pending.
4. **Module loaded via `dlopen`** — works on Simulator; static linking of the
   generated module is the App Store-compatible target.
5. **Simulator-only evidence** — physical-device signing, performance, memory,
   and controller behavior are untested.
6. **No interactive touch acceptance yet** — touch controls render; automated
   input probes use the pipe device.
7. **Interpreter fallback speed** — un-recompiled/SMC regions fall back to the
   interpreter (no JIT by design); verify in demanding scenes.

## Desktop Stage 1 gaps

1. **Input path not fully proven** — pipe input advances menus, but the
   file-select cursor interaction was worked around rather than cleanly
   understood; interactive plaza/objective/save gates remain open.
2. **SMC warning list present** — DolRecomp reported possible runtime
   code-patching ranges for GMSE01; no dedicated Sunshine patch set applied.
3. **Verbose runtime logging is sparse** after module load.

## Resolved / non-blocking observations

- ModernGekko first configure needed dolphin Externals initialized.
- Module C compile at `-O2` takes ~15-25 minutes (desktop and simulator).
- Early "exit immediately" desktop launches were process-termination
  artifacts, not boot crashes.
