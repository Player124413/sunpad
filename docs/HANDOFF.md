# Handoff

Last updated: 2026-08-07

## One-screen summary

Super Mario Sunshine (`GMSE01`) now runs natively on the **iPhone/iPad
simulators and a physical iPad development build** through SunPad: the DolRecomp-generated module executes through
the ModernGekko/Dolphin-derived compatibility runtime, rendered by Dolphin's
Metal backend into a CAMetalLayer in the UIKit app. Desktop Stage 1 (title,
intro, input) is also proven. The three-dot menu, 1x native/2x-4x render
resolution, and Sunshine touch controls are implemented. Physical-iPad
game-engine audio remains broken and is the highest-priority blocker.

## What works

- Desktop: extract → recompile (0 unknown ops) → arm64 module → Metal launch
  to title/intro; pipe input advances the game.
- iOS/iPadOS Simulator: core + module build (no JIT), app boots the game to
  the title screen and renders gameplay; input advances state; stable process.
- On-device import: document picker → GMSE01 validation → retain → on-device
  extraction → boot from the imported image (verified on the Simulator).
- App UI: three-dot menu, render resolution choices, touch controls, settings
  persistence.
- Physical iPad: signed install, ISO boot, Metal rendering, and touch-control
  acceptance are proven.

## What does not

- Physical-iPad JAudio/DSP music, voices, and effects truncate or disappear;
  see `docs/AUDIO_ISSUE.md`. Physical controllers, broader performance/memory,
  module provisioning beyond the dev GMSE01 build, lifecycle save-flushing,
  and audio-interruption restoration remain open.
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

1. Instrument and fix the JAudio/DSP producer failure described in
   `docs/AUDIO_ISSUE.md`; require a continuous pre-output DSP capture.
2. Module matching/provisioning for imported discs beyond the dev GMSE01
   build.
3. Lifecycle hardening: save flushing before suspension, audio-interruption
   restoration, controller connect/disconnect during gameplay.
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
