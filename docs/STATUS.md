# Status

Last updated: 2026-08-06

Current phase: **SunPad now runs Super Mario Sunshine on the iPhone and iPad
simulators** as an ahead-of-time statically recompiled game module through the
Dolphin-derived compatibility runtime (ModernGekko) with the Metal backend.
The iOS/iPadOS app has the BellPad-inspired three-dot menu, render-resolution
choices, and Sunshine touch controls. The remaining desktop gameplay gates
(plaza/objective/save) and the native macOS app shell are next.

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
| 2 | Native Apple Silicon macOS `.app` proof | Not started (moderngekko-run is the current desktop shell) |
| 3 | Mobile-runtime hardening | **In progress — iOS Simulator core built; JIT disabled; interpreter + software-vertex fallbacks** |
| 4 | iPhone + iPad apps | **In progress — GMSE01 boots to title and renders gameplay on iPhone and iPad simulators** |

## What works right now

### iOS / iPadOS (new)

1. The ModernGekko / Dolphin-derived runtime builds as an arm64 iOS Simulator
   binary (`platform IOSSIMULATOR`, minos 16.0, sdk 26.5).
2. The GMSE01 recompiled module builds for the iOS Simulator (arm64).
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
7. BellPad-inspired overlay: three-dot menu, Native/1x/2x/3x/4x render
   resolution, touch controls, opacity/size/hide/edit-layout settings.
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
12. **iOS audio**: native AVAudioEngine backend feeding the Dolphin Mixer at
    48 kHz (audible on the Simulator).

### Desktop (previously proven)

1. Disc extract via DolRecomp native GameCube extractor.
2. `main.dol` static recompilation with 0 unknown instructions (221 chunks).
3. Host module packaging: arm64 `gGMSE01_recomp.dylib`.
4. `moderngekko-run` launches on Apple Silicon with Metal at 30 FPS through
   the title/intro sequences and responds to pipe input.

## What does not work / not yet proven

- iOS audio is a Null backend (cubeb is macOS-only in this tree); an
  AVAudioSession-backed backend is a follow-up.
- The recompiled module is provisioned from the Mac toolchain (iOS has no C
  compiler); import/extract/boot works on-device.
- The mobile render-resolution setting persists but is not yet applied to the
  live EFB scale.
- Physical-device runs (signing, performance, memory) are not yet done.
- Desktop Stage 1: plaza gameplay, objective completion, save/reload evidence.
- No SunPad-native macOS app shell yet.

## Next highest-priority tasks

1. iOS: on-device game-data import (document picker, ISO validation,
   extraction, module provisioning) so a real device can boot.
2. iOS: apply the render-resolution setting to the running runtime (EFB
   scale), add AVAudioSession audio, interactive touch-control acceptance.
3. Stage 2: native macOS SunPad `.app` shell on the shared runtime layer.
4. Desktop Stage 1 gates: plaza gameplay, objective, save/reload evidence.

## Evidence locations (local, gitignored)

- Screenshots: `artifacts/screenshots/2026-08-06/`
  - `iphone-title-screen.png`, `iphone-title-logo.png`,
    `iphone-gameplay-after-input.png`, `ipad-isle-delfino.png`,
    `ipad-title-screen.png`
- iOS core build: `ref/ModernGekko/build-ios3/`
- Simulator module: `/tmp/module-ios2/gGMSE01_recomp.dylib`
