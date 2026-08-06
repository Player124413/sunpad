# Handoff

Last updated: 2026-08-06

## One-screen summary

Super Mario Sunshine (`GMSE01`) now runs natively on the **iPhone and iPad
simulators** through SunPad: the DolRecomp-generated module executes through
the ModernGekko/Dolphin-derived compatibility runtime, rendered by Dolphin's
Metal backend into a CAMetalLayer in the UIKit app. Desktop Stage 1 (title,
intro, input) is also proven. The three-dot menu, Native/1x-4x render
resolution, and Sunshine touch controls are implemented.

## What works

- Desktop: extract → recompile (0 unknown ops) → arm64 module → Metal launch
  to title/intro; pipe input advances the game.
- iOS/iPadOS Simulator: core + module build (no JIT), app boots the game to
  the title screen and renders gameplay; input advances state; stable process.
- On-device import: document picker → GMSE01 validation → retain → on-device
  extraction → boot from the imported image (verified on the Simulator).
- App UI: three-dot menu, render resolution choices, touch controls, settings
  persistence.

## What does not

- iOS audio (Null backend), physical-device runs, module provisioning for
  discs beyond the dev-provisioned GMSE01 build.
- Desktop Stage 1 gates: plaza gameplay, objective, save/reload.
- Native macOS SunPad `.app` shell.

## Exact resume commands

```sh
cd /Users/chrissotraidis/GitHub/sunpad
./scripts/ios-build-core.sh        # iOS core + module + provisioning
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
xcrun simctl boot "iPhone 17 Pro"   # one simulator at a time
xcrun simctl install "iPhone 17 Pro" \
  /tmp/sunpad-ddp/Build/Products/Debug-iphonesimulator/SunPad.app
xcrun simctl launch "iPhone 17 Pro" com.sunpad.SunPad
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/evidence.png
```

Input probe (proves the pipe path on iOS):

```sh
CONTAINER=$(xcrun simctl get_app_container "iPhone 17 Pro" com.sunpad.SunPad data)
python3 scripts/gcpipe.py --pipe \
  "$CONTAINER/Library/Application Support/SunPad/Pipes/sunpad" --tap START
```

Desktop:

```sh
cd ref/ModernGekko-Template
./lib/ModernGekko/build/moderngekko-run --game extracted/Super-Mario-Sunshine \
  --module "$(cat build/modules/GMSE01/active-module.txt)" --graphics Metal
```

## Next actions

1. iOS on-device import: document picker → validate GMSE01 (header, size,
   SHA-256) → extract → boot with the provisioned module (done; module
   matching for other discs remains).
2. Apply the render-resolution setting to the live runtime
   (`Config::GFX_EFB_SCALE`); add an AVAudioSession audio backend.
3. Interactive touch-control acceptance on the Simulator.
4. Stage 2: native macOS SunPad `.app` shell on the shared runtime.
5. Desktop: plaza gameplay, objective, save/reload evidence.

## Do not

- Commit the ISO, extracted FS, generated C/module binaries, saves, or
  `apple/ios/Provisioned/`.
- Claim full decompilation or complete playability yet.
- Run more than one Simulator at a time.

## Input notes

- The pipe device (`Pipes/sunpad`) carries normalized input; commands:
  `PRESS/RELEASE <BUTTON>` and `SET MAIN|C <x> <y>` with x/y in [0,1]
  (0.5 = neutral). `gcpipe.py` encodes this.
- Desktop user config: `~/.local/share/moderngekko/Config/`.
