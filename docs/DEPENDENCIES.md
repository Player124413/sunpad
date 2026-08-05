# Dependencies

Last updated: 2026-08-05

## Host toolchain (verified on this machine)

| Tool | Version / path | Purpose |
|---|---|---|
| macOS | 26.5 (25F71) | Host OS |
| Architecture | arm64 Apple Silicon | Required product architecture |
| Xcode | 26.6 (17F113) | AppleClang, SDKs, simulators |
| AppleClang | 21.0.0.21000101 | C/C++ compiler |
| CMake | 3.27.1 (`/opt/homebrew/bin/cmake`) | Build system |
| Ninja | present (`/opt/homebrew/bin/ninja`) | Generator/build backend |
| Git | 2.41.0 | Source control / submodules |
| Python 3 | 3.11.10 | Scripts, decomp tooling |
| gh | present | Repository research |

## External repositories (pinned)

| Component | URL | Local path | Pinned revision | License | Purpose |
|---|---|---|---|---|---|
| ModernGekko | https://github.com/ExpansionPak/ModernGekko | `ref/ModernGekko` | `048c426ba3db0369e40826d22ad3adcce7fe7c58` | GPL-3.0 | GameCube/Wii recomp runtime (Dolphin-derived) |
| ModernGekko vendor dolphin/RecompCore branch | https://github.com/ExpansionPak/RecompCore (`moderngekko-vendor`) | `ref/ModernGekko/vendor/dolphin` | `e13ab348f13cd67879f6db6e9d7185410f8f62c6` | Dolphin-derived / mixed | Vendored runtime core used by ModernGekko |
| ModernGekko-Template | https://github.com/ExpansionPak/ModernGekko-Template | `ref/ModernGekko-Template` | `1ee85bb5e09c38f493a09f5fa6e9dc8228b23e42` | none declared in GitHub metadata | Reproducible extract/recompile/run Makefile pipeline |
| DolRecomp | https://github.com/ExpansionPak/DolRecomp | `ref/DolRecomp` | `48c4ef11dd59c7367a3479a433e39a35bda80695` | GPL-3.0 | Static PowerPC recompiler (DOL → C/LLVM) |
| RecompCore (top-level clone) | https://github.com/ExpansionPak/RecompCore | `ref/RecompCore` | `af7a1a4854ee243b92926875e5a6b66663b0fda0` | NOASSERTION / Dolphin-derived | Upstream continuation referenced by ModernGekko |
| Super Mario Sunshine decomp | https://github.com/doldecomp/sms | `ref/sms` | `5a8c71edd157a73e09cf62d7faaa3821feaf9913` | CC0-1.0 (project scaffolding; no assets) | Matching decompilation reference; **not** SunPad’s runtime path |
| StrikersRecomp | https://github.com/aharonahdoot/StrikersRecomp | `ref/StrikersRecomp` | `cd88f71f5a836c103484c038454b4143000d883c` | GPL-3.0 | Worked example of DolRecomp + runtime packaging for another GameCube title |
| BellPad | https://github.com/chrissotraidis/bellpad | `ref/bellpad` | local checkout | project license in tree | Apple platform UX/integration reference for Animal Crossing |

## Local non-redistributable materials

| Material | Local path | Notes |
|---|---|---|
| Super Mario Sunshine USA ISO | `ref/Super Mario Sunshine.iso` | User-supplied; never commit/publish |
| BellPad nested build trees / retail AC image (if present inside bellpad) | under `ref/bellpad` | Reference only; do not republish game data |

## Smallest coherent dependency set selected for Stage 1

Required now:

1. **DolRecomp** — generate portable C (or later LLVM objects) from `main.dol`.
2. **ModernGekko** (+ vendored dolphin/RecompCore branch and required Externals) — host runtime, module packaging, launch.
3. **ModernGekko-Template** — orchestrates extract → recompile → module → run.

Useful but secondary:

- **doldecomp/sms** — symbols/maps/progress for research; not a playable native path by itself.
- **StrikersRecomp** — packaging and game-specific HLE patterns as an analogy.
- **BellPad** — Apple app structure for Stages 2–4.

Not selected as primary runtime:

- Standalone generic Dolphin JIT frontend as the product.
- Incomplete matching decompilation as the sole executable core.

## Build requirements implied by upstream

- C11 / C++23 toolchain (AppleClang verified for template compiler check).
- CMake + Ninja + pkg-config + Git + Python.
- ModernGekko dolphin vendor Externals for SDL, zlib-ng, libspng, VMA, cubeb, SPIRV-Cross, libusb (initialized locally as needed).
- No game data is downloaded by these repositories.

## Update policy

When any external checkout moves, update this file with the new SHA and the reason for the bump. Prefer official ExpansionPak / doldecomp upstreams over stale forks.
