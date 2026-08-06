# SunPad

Native macOS, iPhone, and iPad project for Super Mario Sunshine.

SunPad aims to run Super Mario Sunshine as **ahead-of-time statically recompiled game CPU code through a GameCube compatibility runtime** on Apple Silicon. It is **not** a claim that Sunshine is fully decompiled, and it is **not** a pure high-level rewrite. The product path must not depend on a runtime PowerPC JIT.

This repository does **not** include Super Mario Sunshine, disc images, extracted assets, or generated game-derived modules. You must supply your own legally obtained disc image.

## Current status

| Target | Status |
|---|---|
| Stage 1 desktop recompilation (ModernGekko + DolRecomp) | **Title/intro/input proven on Apple Silicon** |
| Apple Silicon macOS app | Not started (moderngekko-run is the current shell) |
| iPhone Simulator | **Game boots, renders, and responds to input** |
| iPad Simulator | **Game boots to the title screen** |
| Physical iPhone / iPad | Not yet (import flow + signing pending) |

As of the latest handoff:

- Local development target disc: **GMSE01** (USA) Rev 0.
- Public tooling cloned and pinned under `ref/`.
- DolRecomp extracts the disc and recompiles `main.dol` with **0 unknown instructions** (~901k decoded ops, 221 C chunks).
- ModernGekko builds native **arm64** `moderngekko-port` / `moderngekko-run`.
- The iOS/iPadOS app statically links the ModernGekko core and runs the game
  on the Simulator with Dolphin's Metal backend (no runtime JIT). Evidence:
  Super Mario Sunshine title screen and gameplay rendering on iPhone 17 Pro
  and iPad Pro 13-inch simulators; pipe input advances the game.
- Screenshot evidence reaches the Shine logo, opening map/airplane sequence, Mario/Toadsworth cabin cutscene, and the "Nintendo Presents Super Mario Sunshine" title card at ~30 FPS.
- Delfino Plaza gameplay, objective completion, and save/reload remain open Stage 1 gates.

See [docs/STATUS.md](docs/STATUS.md) and [docs/HANDOFF.md](docs/HANDOFF.md).

## What this is (precise wording)

SunPad uses:

1. **DolRecomp** to translate the game’s PowerPC DOL into portable host C ahead of time.
2. A **Dolphin-derived ModernGekko / RecompCore compatibility runtime** for GameCube hardware and OS services (graphics, audio, disc, PAD, etc.).
3. A future Apple-native shell inspired by [BellPad](https://github.com/chrissotraidis/bellpad) for menus, controllers, touch controls, and lifecycle.

Matching decompilation (`doldecomp/sms`) is a research reference only. It is incomplete and is not the product runtime.

## Legal boundary

- No Nintendo copyrighted assets are redistributed here.
- Generated recompilation output stays local and gitignored.
- Bring your own legally obtained Super Mario Sunshine disc image.

Details: [docs/LEGAL_AND_PROVENANCE.md](docs/LEGAL_AND_PROVENANCE.md).

## Supported game data (development target)

| Field | Value |
|---|---|
| Game | Super Mario Sunshine |
| Disc ID | `GMSE01` |
| Region | USA |
| Revision | 0 |
| Local size | 1,459,978,240 bytes |
| SHA-256 | `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d` |

## Stage 1 build (research reproduction)

On Apple Silicon with Xcode, CMake, Ninja, and Git:

```sh
# tools live under ref/; product scaffolding is at repo root
cd ref/ModernGekko-Template
# lib/ModernGekko -> ../../ModernGekko, lib/DolRecomp -> ../../DolRecomp
make check FETCH=0
# configure/build ModernGekko after required vendor Externals are present
# then:
./lib/ModernGekko/build/moderngekko-port build extracted/Super-Mario-Sunshine \
  --backend c --toolchain clang --output build/modules
./lib/ModernGekko/build/moderngekko-port run extracted/Super-Mario-Sunshine \
  --backend c --toolchain clang --output build/modules
```

Exact commands, pins, and known issues: [docs/BUILDING.md](docs/BUILDING.md), [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md), [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## iOS / iPadOS build (Simulator)

```sh
./scripts/ios-build-core.sh   # builds the iOS Simulator core + GMSE01 module and provisions the app
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" /tmp/sunpad-ddp/Build/Products/Debug-iphonesimulator/SunPad.app
xcrun simctl launch "iPhone 17 Pro" com.sunpad.SunPad
```

Run one Simulator at a time. The dev build reads a local provisioning
manifest (`apple/ios/Provisioned/dev-config.plist`, gitignored) that points at
the extracted game tree and the Simulator module; the document-picker import
flow is the next milestone.

## Documentation

- [STATUS](docs/STATUS.md)
- [ARCHITECTURE](docs/ARCHITECTURE.md)
- [RESEARCH](docs/RESEARCH.md)
- [DEPENDENCIES](docs/DEPENDENCIES.md)
- [BUILDING](docs/BUILDING.md)
- [TESTING](docs/TESTING.md)
- [MACOS](docs/MACOS.md)
- [IOS_IPADOS](docs/IOS_IPADOS.md)
- [KNOWN_ISSUES](docs/KNOWN_ISSUES.md)
- [HANDOFF](docs/HANDOFF.md)
- [LEGAL_AND_PROVENANCE](docs/LEGAL_AND_PROVENANCE.md)

## Controls

GameCube controls are implemented in the iOS/iPadOS touch layout inspired by
BellPad and adapted for Sunshine: main stick (movement), C-stick (camera),
A/B/X/Y/Z/Start/L/R, plus GameController input that auto-hides the touch
controls. The three-dot menu offers Native/1×/2×/3×/4× render resolution,
touch-control size/opacity/hide/edit-layout settings, and reset. Analog
triggers (FLUDD pressure) and per-control layout persistence are in progress.

## License / third parties

Upstream recompiler and runtime components are primarily GPL / Dolphin-derived. See dependency pins and their upstream licenses before distributing binaries.
