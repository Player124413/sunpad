# Known Issues

Last updated: 2026-08-07

## iOS / iPadOS

1. **Physical-device game audio is broken** — THP video audio is generally
   audible, but game-engine music, voices, and effects truncate after their
   initial buffers or remain silent. Raw DSP captures show the truncation
   before the Apple output backend. The supported ISO has complete audio in
   stock Dolphin. See [AUDIO_ISSUE.md](AUDIO_ISSUE.md) for measurements,
   failed experiments, and the remaining static-recompiler timing lead.
2. **Module provisioning** — import/extract/boot works on-device, but the
   recompiled module is provisioned from the Mac (`dev-config.plist`); iOS has
   no C compiler, so the module for a given disc must be produced by the Mac
   toolchain and matched by game ID.
3. **Lifecycle stubs** — backgrounding/pause hooks exist, but save flushing
   before suspension and audio-interruption restoration are not implemented
   (Stage 4 lifecycle gate).
4. **Module loaded via `dlopen`** — works on Simulator; static linking of the
   generated module is the App Store-compatible target.
5. **Developer-only device provisioning** — the signed app, retained ISO,
   extracted root, and generated module have run on an attached iPad, but the
   module injection path is a development workflow rather than distribution
   packaging.
6. **Interpreter fallback speed** — un-recompiled/SMC regions fall back to the
   interpreter (no JIT by design); verify in demanding scenes.
7. **Physical-controller acceptance pending** — touch controls have been used
   on a physical iPad, but connect/disconnect and auto-hide behavior still need
   hands-on controller coverage.

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
