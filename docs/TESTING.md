# Testing

Last updated: 2026-08-06

## Principles

- Compilation success is not gameplay success.
- Capture dated evidence: target, OS, build config, git revision, game
  version, commands, logs, screenshots, result, remaining defects.
- Run only one Simulator at a time on this machine.

## Game under test

- Disc: Super Mario Sunshine USA, `GMSE01` Rev 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## iOS / iPadOS evidence (2026-08-06)

| Check | Result | Evidence |
|---|---|---|
| iOS Simulator core build (arm64, IOSSIMULATOR) | Pass | `ref/ModernGekko/build-ios3`, `vtool` shows platform IOSSIMULATOR minos 16.0 |
| GMSE01 simulator module build | Pass | `/tmp/module-ios2/gGMSE01_recomp.dylib` (platform IOSSIMULATOR) |
| App link (static core + Metal + GameController) | Pass | `xcodebuild ... BUILD SUCCEEDED` |
| iPhone 17 Pro Simulator boot | Pass | title screen rendered; process stable (PID held) |
| iPhone attract/demo + gameplay rendering | Pass | LIFE/WATER HUD + coins rendered after input |
| iPhone input through pipe device | Pass | START presses advanced the game state |
| iPad Pro 13-inch Simulator boot | Pass | "Welcome to Isle Delfino" splash → title screen |
| No runtime JIT | Pass | JitArm64 fallback disabled; generic vertex loader; no w^x writes |
| On-device import+extract | Pass | Picker validation (magic+GMSE01), private retain, 174-file extraction matches desktop tree |
| Boot from imported image | Pass | iPhone Simulator boots intro from on-device-extracted root and advances on input |
| Landscape presentation | Pass | App is landscape-only; BellPad-style layout verified on iPhone and iPad Simulators |
| Merged input + D-pad | Pass | Mixer (OR buttons/latching, strongest sticks, max triggers); D-pad renders; input advances the game |
| iOS audio backend | Pass | AVAudioEngine + AVAudioSourceNode at 48 kHz; no audio-related crash |
| Startup stability | Pass | Render-scale pre-boot crash fixed; app stays alive across relaunches |

Screenshots: `artifacts/screenshots/2026-08-06/`.

Commands used:

```sh
./scripts/ios-build-core.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" /tmp/sunpad-ddp/Build/Products/Debug-iphonesimulator/SunPad.app
xcrun simctl launch "iPhone 17 Pro" com.sunpad.SunPad
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/sunpad-core.png
# input probe (host writes to the app's pipe device):
CONTAINER=$(xcrun simctl get_app_container "iPhone 17 Pro" com.sunpad.SunPad data)
python3 scripts/gcpipe.py --pipe "$CONTAINER/Library/Application Support/SunPad/Pipes/sunpad" --tap START
```

## Stage 1 desktop checklist

| Check | Status | Evidence |
|---|---|---|
| Disc identity/hash | Pass | `file` + SHA-256 |
| Extract disc | Pass | `dolrecomp extract` → `sys/main.dol` |
| Recompile main.dol, 0 unknown ops | Pass | 0 unknown; 221 chunks |
| Host module | Pass | arm64 `gGMSE01_recomp.dylib` |
| Launch runtime | Pass | module loaded, Metal window |
| Title / intro | Pass | Shine logo, cabin, Isle Delfino; 30 FPS |
| Controller/keyboard input | Partial | pipe input proven; interactive acceptance open |
| Load playable area | Partial | airstrip gameplay reached on desktop; plaza pending |
| Objective / save / reload | Pending | |
| Extended session | Partial | multi-minute holds; multi-hour not done |
