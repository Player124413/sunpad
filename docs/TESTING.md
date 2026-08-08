# Testing

Last updated: 2026-08-07

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
| Simulator audio output | Pass | AVAudioEngine + AVAudioSourceNode at 48 kHz; no audio-related crash |
| Startup stability | Pass | Render-scale pre-boot crash fixed; app stays alive across relaunches |
| Runtime diagnostics | Pass | Overlay FPS readout (30.0 at 640x528 EFB) and EFB resolution via PerformanceMetrics |

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

### Re-verification before merge (2026-08-06)

Run at git revision `d3c1ed8` (docs-only changes since do not affect the app
artifact) on this machine, iPhone 17 Pro Simulator (iOS 26.5), Debug build,
after an incremental `./scripts/ios-build-core.sh` (core + module + merged
static archive) and `xcodebuild` app build:

| Check | Result | Evidence |
|---|---|---|
| Core + module + provisioning pipeline | Pass | `ios-build-core.sh` completed; `libSunPadCore.a` merged |
| App build | Pass | `xcodebuild ... BUILD SUCCEEDED` |
| Launch + boot | Pass | "Welcome to Isle Delfino" splash rendered (~29-30 FPS) |
| Pipe input advances the game | Pass | `gcpipe.py --tap START` moved the splash into the Peach/Mario cabin intro cutscene |
| Stability | Pass | App stayed alive across relaunch (one unrelated Simulator shutdown required a `simctl boot` + relaunch) |

Screenshots: `artifacts/screenshots/2026-08-06/reverify-2026-08-06-splash.png`,
`artifacts/screenshots/2026-08-06/reverify-2026-08-06-cabin-intro-after-start.png`.

## Physical iPad evidence (2026-08-07)

| Check | Result | Evidence |
|---|---|---|
| Device core + GMSE01 module build | Pass | arm64 iPhoneOS core archive and signed GMSE01 dylib built locally |
| Signed install and launch | Pass | `com.sunpad.SunPad` installed and launched on iPad Pro (12.9-inch, 6th generation) |
| Retained ISO boot | Pass | supported 1,459,978,240-byte GMSE01 image retained and supplied as the boot disc |
| Metal rendering and touch input | Pass | intro/title/gameplay render; touch controls and layout editor used on hardware |
| Game-engine audio | **Fail** | title/menu music and voices truncate or disappear; raw DSP output stops after roughly 39-53 ms |
| Same ISO in stock Dolphin 2606 | Pass | complete title voice and music, ruling out damaged source media |

The physical-device audio failure and its pre-output DSP measurements are
documented in [AUDIO_ISSUE.md](AUDIO_ISSUE.md). A successful Apple output
callback is not an audio acceptance pass.

## Audio root-cause verification (2026-08-08, Apple Silicon Mac)

All rows use Dolphin's producer-side `[DSP] DumpAudio` capture
(`dspdump.wav`, 32,028 Hz) analyzed as 250 ms RMS windows; "loud" =
RMS > 40. Desktop rows run `moderngekko-run` in iOS-parity mode
(`STATICRECOMP_NO_FALLBACK_JIT=1`), which is required on Apple Silicon
because the fallback JIT otherwise takes over execution (yield hook is
Jit64-only).

| Check | Result | Evidence |
|---|---|---|
| Desktop parity, unfixed timebase | Audio continuous at RMS level | 84.6% loud / 113 s; 518M module dispatches |
| Desktop parity, fixed timebase | Pass, no regression | 91.8% loud / 113 s; 643M module dispatches |
| Desktop parity, unfixed, ~7% speed (E-cores) | Producer complete in virtual time | 20.7 s virtual captured over 300 s wall, content matches full-speed run |
| iOS Simulator app, fixed core | **Pass** | 92.8% loud over 139 s, boot → title → attract; iPhone 17 Pro sim |
| Physical iPad re-acceptance | **Open** | requires `scripts/ios-build-core-device.sh` rebuild + on-device run |

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
