# SunPad

SunPad is an experimental, native Apple ARM64 source port project for the
original US revision of Super Mario Sunshine for Nintendo GameCube. It runs
the game's PowerPC code as **ahead-of-time statically recompiled host code
through a GameCube compatibility runtime**. It is not a claim that Sunshine is
fully decompiled, and it does not depend on a runtime PowerPC JIT.

<p align="center"><img src="apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="SunPad sunrise app icon"></p>

This repository is ready for cross-machine handoff and acceptance testing. The
proven ARM64 game core (DolRecomp-generated module + ModernGekko/Dolphin-derived
runtime) packages as native **iPhone and iPad simulator apps** that boot Super
Mario Sunshine to the title screen, render gameplay through Metal, accept
touch and GameController input, import user-owned game data through the Files
document picker, extract it on-device, and persist per-device control and
render-resolution settings. The same core launches on Apple Silicon desktop
through `moderngekko-run`. Physical-device runtime, signing, broader scene
coverage, and the native macOS app shell remain explicit follow-up work; this
is a source release, not an App Store release or a claim of production
completeness.

## Current status

As of 2026-08-06:

- A pinned ModernGekko + DolRecomp toolchain translates `main.dol` with
  **0 unknown instructions** (~901k decoded ops, 221 C chunks) and packages a
  native arm64 `gGMSE01_recomp.dylib` for macOS and the iOS Simulator.
- The ModernGekko / Dolphin-derived compatibility runtime builds for the iOS
  Simulator (arm64, `platform IOSSIMULATOR`) with the **static-recomp CPU
  path and no runtime JIT** (interpreter fallback + generic software vertex
  loader).
- The SunPad iOS/iPadOS app statically links the core and renders the game
  through Dolphin's Metal backend into a CAMetalLayer. Evidence on the iPhone
  17 Pro and iPad Pro 13-inch simulators (iOS 26.5): the SUPER MARIO SUNSHINE
  title screen, the attract/demo sequence, and gameplay rendering; input
  advances the intro (cabin/map → Peach cutscene → Isle Delfino).
- The app is **landscape-only** with a BellPad-style control layout: move
  stick bottom-left, D-pad to its right, camera stick bottom-right, A/B/X/Y
  diamond, L/R/Z shoulders, START, and the three-dot menu.
- Game-data import is implemented and verified on-device: Files document
  picker → GameCube header validation (magic + `GMSE01`) → private Application
  Support retain → on-device extraction (174 files, matches the desktop tree)
  → boot from the imported image.
- iOS audio is a native `AVAudioEngine` backend feeding the Dolphin Mixer at
  48 kHz, so the game is audible on the Simulator.
- Touch + GameController merge through one thread-safe normalized GameCube
  state (ORed buttons with edge latching, strongest-wins sticks, max analog
  triggers for FLUDD pressure), with Native/1×/2×/3×/4× render resolution
  applied live.
- Desktop `moderngekko-run` reaches the title/intro at ~30 FPS and responds to
  pipe input. Delfino Plaza gameplay, objective completion, and save/reload
  evidence remain open Stage 1 gates.

## Supported platforms

| Platform | Status |
|---|---|
| Apple Silicon macOS | Proven core + Metal launcher (`moderngekko-run`) reaches title/intro; native SunPad `.app` shell not started |
| iPhone/iPad Simulator | Game boots to title and renders gameplay in landscape; import/extract/input/audio work; hands-on defect acceptance remains |
| Physical iPhone / iPad | Not yet (document-picker import works; module provisioning for other discs + signing pending) |
| Intel macOS, Windows, Linux | Upstream-reference platforms, not SunPad release targets |

## Game-data requirements

SunPad will never include a GameCube image, extracted Nintendo assets, or
generated game-derived modules. Users must supply their own legally obtained,
supported retail data.

The initial compatibility target is:

- Game ID: `GMSE01`
- Region: USA
- Revision: 0

The development target image is `ref/Super Mario Sunshine.iso` (SHA-256
`67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`). Raw
ISO/GCM are recognized; compressed formats are hardening work.

Never add game data to this repository. Root ignore rules cover common disc,
extracted-data, and save formats, and generated recompilation output stays
local and reproducible from the user's disc.

## Game-data import flow

```text
Files document picker
→ validate GameCube header (magic + GMSE01)
→ stage and retain a private Application Support copy
→ extract on-device (sys/ + files/, Dolphin DiscIO)
→ boot the extracted root with the provisioned module
```

This flow is runtime-proven on the iPhone Simulator for a raw GMSE01 ISO. A
valid retained copy and extracted root are reused after relaunch; an invalid
image shows an actionable error and does not replace existing data. The
three-dot menu can request change/reimport while preserving the current image
until the replacement validates, or explicitly remove the retained data. The
recompiled module is produced by the Mac toolchain for the matching disc (iOS
has no C compiler); matching a provisioned module to an imported disc is the
remaining gap.

## Build instructions

On an Apple Silicon Mac with Xcode 26.x, CMake, Ninja, ripgrep, Git, and a
legally obtained GMSE01 ISO:

```sh
git clone https://github.com/chrissotraidis/sunpad.git
cd sunpad
# Desktop reproduction (Stage 1)
cd ref/ModernGekko-Template && make check FETCH=0
# ... see docs/BUILDING.md for the exact extract/recompile/run commands ...
cd ../..
# iOS / iPadOS Simulator app (one command provisions core + module)
./scripts/ios-build-core.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" /tmp/sunpad-ddp/Build/Products/Debug-iphonesimulator/SunPad.app
xcrun simctl launch "iPhone 17 Pro" com.sunpad.SunPad
```

Run one Simulator at a time. Exact commands, pins, and known issues:
[docs/BUILDING.md](docs/BUILDING.md), [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md),
[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## Controls

The mobile layout is landscape-only, inspired by BellPad and adapted for
Sunshine: a left analog stick (movement), a C-stick (camera), A/B/X/Y/Z,
START, L/R, and a D-pad. It scales from compact iPhones to an expanded iPad
layout and respects safe areas. The top-right three-dot menu opens native
settings: render resolution (Native plus 1×, 2×, 3×, 4× EFB scales), control
opacity/size, hide-on-controller, Move-mode drag editing with persisted
normalized positions, and Reset. Physical controllers auto-hide the touch
controls on devices. Touch and GameController states merge through one
thread-safe normalized GameCube state: ORed buttons with rising-edge latching,
strongest-wins sticks, and maximum analog triggers (FLUDD pressure on the
analog R trigger). The GameController mapping puts analog triggers on the
trigger buttons, Z on the right shoulder, Start on Menu, and the D-pad on the
D-pad.

Desktop keyboard mapping (via the ModernGekko pipe/ini configuration) maps
A/B/X/Y/Start/Z/L/R, WASD movement, arrow-key C-stick, and Q/E triggers.

## Saves

The desktop path persists a Dolphin-compatible memory card under the
ModernGekko user directory (`~/.local/share/moderngekko/GC/USA/Card A/`).
Memory-card save/reload evidence inside the game (save point → quit →
relaunch → load) is an open Stage 1 gate. Mobile GCI persistence and the
save-export flow are follow-up work modeled on the same Dolphin GCI format.
No user save belongs in Git, an app bundle, or an IPA.

## Architecture

```text
UIKit / Files / GCController / AVAudioSession
                    ↓
          SunPad Apple adapter
                    ↓
       locally generated recompiled module (DolRecomp)
                    ↓
 ModernGekko / Dolphin-derived compatibility runtime
                    ↓
        Dolphin Metal backend (VideoCommon)
                    ↓
                  Metal
```

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Testing

- iOS/iPadOS evidence (2026-08-06): screenshots in
  `artifacts/screenshots/2026-08-06/`; core/module platform verified with
  `vtool` (`platform IOSSIMULATOR`, arm64); landscape boot, gameplay
  rendering, input, import/extract, audio, and the control layout observed on
  the iPhone 17 Pro Simulator.
- Desktop Stage 1 evidence: title/intro rendering at ~30 FPS; pipe input
  advances the game.
- See [docs/TESTING.md](docs/TESTING.md) for dated checklists, commands, and
  remaining defects.

## Known issues

See [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md). Highlights: physical-device
audio/controllers/performance are untested; the module is provisioned from the
Mac for a matching disc; desktop plaza/objective/save gates are open.

## Research and credits

The recompilation path follows the public ExpansionPak ecosystem (DolRecomp,
ModernGekko, ModernGekko-Template, RecompCore) and uses
[doldecomp/sms](https://github.com/doldecomp/sms) as a research reference.
"ReShine" is treated as non-public/community-reported; SunPad reproduces the
generic pipeline from the local GMSE01 image. See
[docs/RESEARCH.md](docs/RESEARCH.md).

## Legal

SunPad is unofficial and is not affiliated with or endorsed by Nintendo.
Super Mario Sunshine, Nintendo, and GameCube names are used only to describe
compatibility. No disc image, original copyrighted game asset, extracted data,
or generated game-derived module is included in this repository or any
release. Users are responsible for supplying their own legally obtained
supported game data. See
[docs/LEGAL_AND_PROVENANCE.md](docs/LEGAL_AND_PROVENANCE.md) and the mixed
upstream licenses of the dependency pins in
[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

## Contributing

SunPad is a research/experimental project. The best way to help is to test a
Simulator build with your own legally obtained GMSE01 image and file defects
with the evidence template in [docs/TESTING.md](docs/TESTING.md).
