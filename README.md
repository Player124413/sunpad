# SunPad

Native macOS, iPhone, and iPad project for Super Mario Sunshine.

SunPad aims to run Super Mario Sunshine as **ahead-of-time statically recompiled game CPU code through a GameCube compatibility runtime** on Apple Silicon. It is **not** a claim that Sunshine is fully decompiled, and it is **not** a pure high-level rewrite. The product path must not depend on a runtime PowerPC JIT.

This repository does **not** include Super Mario Sunshine, disc images, extracted assets, or generated game-derived modules. You must supply your own legally obtained disc image.

## Current status

| Target | Status |
|---|---|
| Stage 1 desktop recompilation (ModernGekko + DolRecomp) | **Title/intro proven on Apple Silicon** |
| Apple Silicon macOS app | Not started |
| iPhone / iPad | Not started |

As of the latest handoff:

- Local development target disc: **GMSE01** (USA) Rev 0.
- Public tooling cloned and pinned under `ref/`.
- DolRecomp extracts the disc and recompiles `main.dol` with **0 unknown instructions** (~901k decoded ops, 221 C chunks).
- ModernGekko builds native **arm64** `moderngekko-port` / `moderngekko-run`.
- Packaged arm64 `gGMSE01_recomp.dylib` launches through Metal.
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

## Controls (planned)

GameCube controls will be mapped for macOS keyboard/GameController and mobile touch layouts inspired by BellPad, adapted for Sunshine (movement, C-stick camera, A/B/X/Y/Z/Start/L/R, analog triggers / FLUDD pressure).

## License / third parties

Upstream recompiler and runtime components are primarily GPL / Dolphin-derived. See dependency pins and their upstream licenses before distributing binaries.
