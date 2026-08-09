# Known Issues

Last updated: 2026-08-09

## iOS / iPadOS

1. **Game audio: timebase bug fixed, device re-acceptance pending** — the
   static-recomp core ran the guest timebase 12× fast inside native bursts
   and snapped it backwards at burst boundaries, breaking JAudio's
   tick-delta-based voice limiter. Fixed 2026-08-08
   (`patches/ModernGekko-dolphin/`); producer-side audio verified continuous
   on desktop parity runs and the iOS Simulator app. A physical-iPad
   re-acceptance run is still required; if audible defects persist there
   with a clean DSP dump, debug the iOS output/consumer chain (Mixer iOS
   modifications and CoreAudio backend). See [AUDIO_ISSUE.md](AUDIO_ISSUE.md).
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
7. **Physical-controller crash fixed; re-acceptance pending** — seven retained
   iPad crash reports from 2026-08-08 show the same stack-buffer abort in
   `SunPadCoreHost::publishInput`. The GameController callback left the button
   bitmask uninitialized, and the resulting random multi-button edges could
   overrun a fixed 128-byte pipe-command buffer. Controller snapshots are now
   zero-initialized and commands use dynamically sized storage. The corrected
   build still needs an exact wired-controller + HDMI hands-on acceptance run.
8. **Physical iPhone performance is less than ideal** — an iPhone 14 can run
   substantially below full speed even at 1×. The runtime and module are
   release-optimized; the portable software vertex loader and interpreter
   fallback remain likely CPU costs. Profile native dispatch and fallback
   counters before attempting device-specific tuning. The current iPad target
   provides the better mobile experience.
9. **Experimental wide output** — Original 4:3 is the stable default on both
   iPhone and iPad. The 16:9 and Fill Screen menu choices use Dolphin's
   widescreen/custom-aspect paths and can expose projection, culling, or
   stretching defects. They change game rendering only; touch controls keep
   their normal device layout.
10. **Sustained CPU diagnostics** — physical iPad runs commonly exceed iPadOS's
    diagnostic threshold (roughly 58–99% average CPU in retained reports), but
    every inspected `cpu_resource` report says `Action taken: none`. This is a
    performance/energy concern, not evidence that iPadOS killed the app in the
    2026-08-08 controller crash sequence.
11. **Older deployment targets are configured, not yet artifact-verified** —
    the earlier generated physical-device module reported iOS 26.5 as its
    minimum even though the app target was iOS 16.0. The current core/module
    scripts now set iOS 16.0 explicitly, and the desktop/package path sets
    macOS 14.0. Fresh complete builds still need minimum-OS inspection across
    all final Mach-O files plus runtime acceptance on the oldest claimed OS;
    the configuration alone is not a compatibility result.
12. **CoreDevice removing uploads are unsafe for provisioning** — on the
    currently used iOS 26.5.2/Xcode toolchain, a nested `devicectl device copy
    to` with `--remove-existing-content true` cleared unrelated app-container
    data. Provision the module before user data and use a non-removing
    directory overlay. Back up and read back each device's saves and settings;
    never treat an app-install success message as preservation proof.

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
