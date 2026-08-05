# Status

Last updated: 2026-08-05

Current phase: **Stage 1 nearly complete for boot/title** — Super Mario Sunshine AOT recompilation launches natively on Apple Silicon through ModernGekko/Metal and reaches the intro/title sequence. Stage 2 (SunPad macOS app shell) is next after controller/plaza gameplay verification.

## Confirmed local materials

- Disc: `ref/Super Mario Sunshine.iso`
  - Disc ID: `GMSE01` USA Rev 0
  - Size: 1,459,978,240 bytes
  - SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`
- Public toolchain clones under `ref/` (pinned in DEPENDENCIES.md)
- BellPad reference under `ref/bellpad`

## Architecture stance

Ahead-of-time statically recompiled game CPU code running through a Dolphin-derived GameCube compatibility runtime (ModernGekko / RecompCore lineage). Not a full matching decompilation, and not a pure high-level rewrite. Product path must not depend on a runtime PowerPC JIT.

## Stage gates

| Stage | Goal | Status |
|---|---|---|
| 1 | Reproduce Sunshine recompilation to playable desktop session | **In progress — title/intro proven** |
| 2 | Native Apple Silicon macOS `.app` proof | Not started |
| 3 | Mobile-runtime hardening | Not started |
| 4 | iPhone + iPad apps | Not started |

## What works right now

1. **Disc extract** via DolRecomp native GameCube extractor.
2. **main.dol static recompilation** with **0 unknown instructions**:
   - text0: 2320 decoded, 0 unknown
   - text1: 898736 decoded, 0 unknown
   - 221 generated C chunks
   - SMC/runtime-patch warning list produced (`generated_smc.txt`, 138 ranges)
3. **Host module packaging**: `gGMSE01_recomp.dylib` built as **Mach-O arm64** (~82 MB).
4. **Runtime launch**:
   - `moderngekko-run` (Mach-O arm64) loads the module
   - Metal graphics backend selected
   - Window title reports `ModernGekko - Super Mario Sunshine [GMSE01] | 30.0 FPS`
5. **Gameplay evidence captured**:
   - Shine Sprite title/logo sequence
   - Opening airplane/map intro sequence
   - Cabin cutscene with Mario and Toadsworth
6. Extended session held for tens of seconds without immediate crash while rendering intro/title content.
7. Repository scaffold, docs, ignore rules, and Stage 1 helper scripts.

## What does not work / not yet proven

- Full Stage 1 gate is not closed:
  - Reliable controller/keyboard input acceptance through menus into Delfino Plaza not yet proven with clean before/after evidence.
  - FLUDD / camera / objective completion not yet tested.
  - Save and reload not yet tested.
  - Long-session stability not yet measured.
- No SunPad-native macOS/iOS application shell yet (still using moderngekko-run research launcher).
- Sunshine-specific runtime patches not yet isolated; generic ModernGekko path currently reaches intro/title without custom game patches.

## ReShine note

No public ReShine repository was found. ModernGekko credits binsento for a Sunshine recomp, but sources/patches are not published. Current path is generic DolRecomp + ModernGekko reproduction from the local GMSE01 image.

## Next highest-priority tasks

1. Prove keyboard/GameController input from title into file select / new game.
2. Reach Delfino Plaza (or equivalent playable hub), control Mario/FLUDD, complete one objective.
3. Prove memory-card save/reload.
4. Begin Stage 2 SunPad macOS `.app` shell using BellPad UX patterns while reusing the AOT module + runtime.

## Evidence locations (local, gitignored)

- Logs: `artifacts/runtime/2026-08-05-*.log`
- Screenshots: `artifacts/runtime/2026-08-05-screen.png`, `title-*.png`
- Module: `ref/ModernGekko-Template/build/modules/GMSE01/.../gGMSE01_recomp.dylib`
