# Known Issues

Last updated: 2026-08-07

## iOS / iPadOS

1. **Game audio: timebase bug fixed, device re-acceptance pending** — the
   static-recomp core ran the guest timebase 12× fast inside native bursts
   and snapped it backwards at burst boundaries, breaking JAudio's
   tick-delta-based voice limiter. Fixed 2026-08-08
   (`patches/ModernGekko-dolphin/`); producer-side audio verified continuous
   on desktop parity runs and the iOS Simulator app. A physical-iPad
   re-acceptance run is still required; if audible defects persist there
   with a clean DSP dump, debug the iOS output/consumer chain (Mixer iOS
   modifications, AudioQueue/CoreAudio). See [AUDIO_ISSUE.md](AUDIO_ISSUE.md).
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

0. **Fallback JIT hogs execution on Apple Silicon** — the JIT-to-module
   yield hook (`StaticRecompShouldYieldAt`) is only wired into the Jit64
   (x86) dispatcher, so on arm64 desktops the fallback JitArm64 takes over
   at the first non-module address and never returns; prior desktop
   "static recomp" evidence mostly exercised Dolphin's JIT. Run with
   `STATICRECOMP_NO_FALLBACK_JIT=1` for the true module + interpreter
   contract (matches iOS). Wiring the yield hook into JitArm64 is open work.
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
