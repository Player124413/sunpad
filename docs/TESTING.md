# Testing

Last updated: 2026-08-05

## Principles

- Compilation success is not gameplay success.
- Capture dated evidence: target, OS, build config, git revision, game version, commands, logs, screenshots, result, remaining defects.

## Game under test

- Disc: Super Mario Sunshine USA
- ID: `GMSE01` Rev 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## Stage 1 checklist

| Check | Status | Evidence |
|---|---|---|
| Disc identity/hash | Pass | `file` + Python header/hash |
| Toolchain check | Pass | `make check` AppleClang 21 arm64 |
| Build DolRecomp/ModernGekko | Pass | arm64 `dolrecomp`, `moderngekko-port`, `moderngekko-run` |
| Extract disc | Pass | `dolrecomp extract` → `sys/main.dol` |
| Recompile main.dol, 0 unknown ops | Pass | 0 unknown; 221 chunks; recompile log |
| Build host module | Pass | arm64 `gGMSE01_recomp.dylib` (~82 MB) |
| Launch runtime | Pass | module loaded, Metal window |
| Title / intro sequence | Pass | screenshots show Shine logo, map/airplane intro, Mario/Toadsworth cabin; window 30 FPS |
| Controller/keyboard input | Partial | GCPadNew.ini present; scripted keypress attempt run; clean menu-advance proof still open |
| Load playable area | Pending | |
| Complete objective | Pending | |
| Save/reload | Pending | |
| Extended session | Partial | multi-tens-of-seconds intro/title hold observed; multi-hour not done |

## Representative commands used

```sh
cd ref/ModernGekko-Template
./lib/DolRecomp/build/dolrecomp extract "../../Super Mario Sunshine.iso" extracted/Super-Mario-Sunshine
./lib/ModernGekko/build/moderngekko-port build extracted/Super-Mario-Sunshine --backend c --toolchain clang --output build/modules
./lib/ModernGekko/build/moderngekko-run --game extracted/Super-Mario-Sunshine \
  --module "$(cat build/modules/GMSE01/active-module.txt)" --graphics Metal
file lib/ModernGekko/build/moderngekko-run build/modules/GMSE01/*/gGMSE01_recomp.dylib
```

## Architecture evidence

- `moderngekko-run`: Mach-O 64-bit executable arm64
- `gGMSE01_recomp.dylib`: Mach-O 64-bit dynamically linked shared library arm64
- Host: Apple Silicon macOS 26.5 / Xcode 26.6

## Screenshot evidence (local)

- `artifacts/runtime/2026-08-05-screen.png` — Shine Sprite title logo, 30 FPS window title
- `artifacts/runtime/2026-08-05-title-1.png` — airplane map intro
- `artifacts/runtime/2026-08-05-title-3.png` — Mario/Toadsworth cabin cutscene
