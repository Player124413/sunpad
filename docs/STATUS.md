# Status

Last updated: 2026-08-08

Current phase: **SunPad now boots Super Mario Sunshine on a physical iPad as
well as the iPhone and iPad simulators** as an ahead-of-time statically
recompiled game module through the Dolphin-derived compatibility runtime
(ModernGekko) with the Metal backend. Rendering and touch controls work on the
iPad, but game-engine audio remains a confirmed release blocker.

## Confirmed local materials

- Disc: `ref/Super Mario Sunshine.iso`
  - Disc ID: `GMSE01` USA Rev 0
  - Size: 1,459,978,240 bytes
  - SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`
- Public toolchain clones under `ref/` (pinned in DEPENDENCIES.md)
- BellPad reference under `ref/bellpad`

## Architecture stance

Ahead-of-time statically recompiled game CPU code running through a
Dolphin-derived GameCube compatibility runtime (ModernGekko / RecompCore
lineage). Not a matching decompilation, not a pure high-level rewrite, and on
Apple platforms no runtime PowerPC JIT (the static-recomp fallback uses the
interpreter, and the generic vertex loader replaces Dolphin's ARM64
code-generating loader).

## Stage gates

| Stage | Goal | Status |
|---|---|---|
| 1 | Reproduce Sunshine recompilation to playable desktop session | **In progress — title/intro/input proven; plaza/objective/save open** |
| 2 | Native Apple Silicon macOS `.app` proof | **App bundle built, signed, and launched; gameplay acceptance remains** |
| 3 | Mobile-runtime hardening | **In progress — Simulator/device core built; JIT disabled; interpreter + software-vertex fallbacks** |
| 4 | iPhone + iPad apps | **In progress — physical iPad boot/render/input proven; audio blocker open** |

## What works right now

### iOS / iPadOS (new)

1. The ModernGekko / Dolphin-derived runtime builds as arm64 iOS Simulator and
   physical-device binaries (minimum iOS 16.0).
2. The GMSE01 recompiled module builds for the Simulator and a physical arm64
   device development workflow.
3. The SunPad iOS app links the core statically, boots the game on a
   background thread, and renders through Dolphin's Metal backend into a
   CAMetalLayer surface.
4. iPhone 17 Pro Simulator: boots to the SUPER MARIO SUNSHINE title screen,
   plays the attract/demo sequence, and renders gameplay (LIFE/WATER HUD,
   coins); the process stays alive.
5. iPad Pro 13-inch Simulator: boots through the "Welcome to Isle Delfino"
   splash to the title screen.
6. Input works end-to-end on iOS: normalized touch/GameController state is
   written to the Dolphin pipe device and advances the game (START presses
   moved the game from the title into gameplay rendering).
7. BellPad-inspired overlay: three-dot menu, 1x native/2x/3x/4x render
   resolution, original 4:3 plus experimental 16:9/Fill Screen output, touch
   controls, opacity/size/hide/edit-layout settings. Aspect changes do not
   move the separate touch overlay.
8. No runtime PowerPC JIT on iOS: interpreter fallback + software vertex
   loader.
9. **On-device game-data import** is implemented and verified: document
   picker → GMSE01 validation → private retain → on-device extraction
   (174 files, matches the desktop tree) → boot from the imported image.
10. **Landscape-only presentation** with a BellPad-style control layout
    (move stick, D-pad, camera stick, A/B/X/Y, L/R/Z, START, three-dot menu);
    verified on iPhone and iPad simulators.
11. **BellPad-style input merging**: touch + GameController through one
    thread-safe normalized GameCube state (ORed buttons with edge latching,
    strongest-wins sticks, max analog triggers / FLUDD pressure).
12. **Game-engine audio root cause fixed (2026-08-08)**: the static-recomp
    core's guest timebase ran 12× fast inside native bursts and snapped
    backwards at burst boundaries, tripping JAudio's tick-delta voice
    limiter. With the fix, producer-side DSP dumps are continuous on desktop
    parity runs and in the iOS Simulator app (92.8% audible over 139 s).
    Physical-iPad re-acceptance is pending. See `docs/AUDIO_ISSUE.md`.
13. **Runtime diagnostics**: the overlay shows live FPS (30.0 on the iPhone
    17 Pro Simulator at 640x528 EFB) and the current EFB resolution.

### Desktop (previously proven)

1. Disc extract via DolRecomp native GameCube extractor.
2. `main.dol` static recompilation with 0 unknown instructions (221 chunks).
3. Host module packaging: arm64 `gGMSE01_recomp.dylib`.
4. `moderngekko-run` launches on Apple Silicon with Metal at 30 FPS through
   the title/intro sequences and responds to pipe input.
5. A local arm64 `SunPad.app` packages the native launcher/runner/module,
   defaults to Metal, exposes resolution/fullscreen settings, seeds WASD +
   keyboard controls, and allows a connected controller profile to replace
   them. The app bundle passes ad-hoc signing verification and launches.

## What does not work / not yet proven

- Physical-iPad audio re-acceptance with the fixed core has not run yet; the
  2026-08-08 timebase fix is verified on desktop parity runs and the iOS
  Simulator app only. Note the surviving device DSP dump from 2026-08-06 was
  already continuous at music level, so any residual audible defect on
  device should be debugged in the iOS output/consumer chain.
- Desktop caveat: on Apple Silicon the fallback JIT never yields back to the
  recompiled module (yield hook is Jit64-only), so desktop static-recomp
  evidence requires `STATICRECOMP_NO_FALLBACK_JIT=1`.
- The recompiled module is provisioned from the Mac toolchain (iOS has no C
  compiler); import/extract/boot works on-device, but provisioning a module
  for a disc other than the dev-provisioned GMSE01 build is not implemented.
- Physical-iPad signing, install, launch, Metal rendering, ISO boot, and touch
  input are proven. Broader performance and memory acceptance remain open.
- Desktop Stage 1: plaza gameplay, objective completion, save/reload evidence.
- The macOS app shell is proven, but plaza gameplay, objective completion,
  save/reload, and extended-session acceptance remain open.
- Touch controls are usable on physical iPad, including move mode, individual
  sizing, opacity, GameCube-style colors, and a closable settings panel.
- App lifecycle hardening is partial: backgrounding/pause hooks exist but
  save-flushing before suspension and audio-interruption restoration are not
  implemented.

## Next highest-priority tasks

1. Re-run physical-iPad audio acceptance with the fixed core (rebuild via
   `scripts/ios-build-core-device.sh`); use the pre-output capture gate plus
   audible checks in `docs/AUDIO_ISSUE.md`.
2. Module provisioning for imported discs beyond the dev GMSE01 build
   (game-ID matching against the provisioned module).
3. App lifecycle: save flushing before suspension, audio-interruption
   restoration, controller connect/disconnect during gameplay.
4. Desktop/macOS app gates: plaza gameplay, objective, save/reload, connected
   controller, and extended-session evidence.

## Evidence locations (local, gitignored)

- Screenshots: `artifacts/screenshots/2026-08-06/`
  - `iphone-title-screen.png`, `iphone-title-logo.png`,
    `iphone-gameplay-after-input.png`, `ipad-isle-delfino.png`,
    `ipad-title-screen.png`
- iOS core build: `ref/ModernGekko/build-ios3/`
- Simulator module: `/tmp/module-ios2/gGMSE01_recomp.dylib`
