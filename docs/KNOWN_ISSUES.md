# Known Issues

Last updated: 2026-08-06

## iOS / iPadOS

1. **Physical-device audio untested** — the AVAudioEngine backend runs on the
   Simulator, but audio-session interruptions, background audio, and hardware
   behavior on real devices are unverified.
2. **Module provisioning** — import/extract/boot works on-device, but the
   recompiled module is provisioned from the Mac (`dev-config.plist`); iOS has
   no C compiler, so the module for a given disc must be produced by the Mac
   toolchain and matched by game ID.
3. **Lifecycle stubs** — backgrounding/pause hooks exist, but save flushing
   before suspension and audio-interruption restoration are not implemented
   (Stage 4 lifecycle gate).
4. **Module loaded via `dlopen`** — works on Simulator; static linking of the
   generated module is the App Store-compatible target.
5. **Simulator-only evidence** — physical-device signing, performance, memory,
   and controller behavior are untested.
6. **Interactive touch acceptance pending** — touch controls render and
   `scripts/simdrag.swift` posts real drags to the Simulator; hands-on layout
   acceptance on device is not complete.
7. **Interpreter fallback speed** — un-recompiled/SMC regions fall back to the
   interpreter (no JIT by design); verify in demanding scenes.
8. **Physical-device verification pending** — landscape rotation, audio
   session behavior, controller auto-hide, and Metal performance are validated
   on Simulators only so far.

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
