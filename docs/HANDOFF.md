# Handoff

Last updated: 2026-08-05

## One-screen summary

SunPad Stage 1 has a **working native Apple Silicon recompilation path** for Super Mario Sunshine USA (`GMSE01`). DolRecomp recompiles `main.dol` with zero unknown opcodes; ModernGekko packages an arm64 `gGMSE01_recomp.dylib` and launches it through Metal. Screenshot evidence shows the Shine logo, map/airplane intro, cabin cutscenes (Mario/Peach/Toadsworth), and the Isle Delfino welcome sequence at 30 FPS. Full playable plaza/objective/save gates and the SunPad app shell remain.

## What works

- Extract + AOT recompile + module build + launch.
- Metal rendering of intro/title content.
- arm64 host tools and game module (no Rosetta, no JIT product path).

## What does not

- Not yet proven: robust input through menus, Delfino Plaza, FLUDD/camera, objective, save/reload, long soak.
- No polished SunPad `.app` yet.

## Exact resume commands

```sh
cd /Users/chrissotraidis/GitHub/sunpad
./scripts/stage1-status.sh
cd ref/ModernGekko-Template
./lib/ModernGekko/build/moderngekko-port inspect extracted/Super-Mario-Sunshine --output build/modules
./lib/ModernGekko/build/moderngekko-run --game extracted/Super-Mario-Sunshine \
  --module "$(cat build/modules/GMSE01/active-module.txt)" --graphics Metal
```

Controller config currently at:

- `~/.local/share/moderngekko/Config/GCPadNew.ini`
- Keyboard A mapped to key `X`, Start to Return, WASD stick, arrows C-stick, Q/E triggers.

## Next actions

1. From title, prove input advances to file select / new game with screenshots.
2. Reach Delfino Plaza and complete one Shine objective.
3. Test memory-card save/reload.
4. Start Stage 2 macOS app shell (BellPad-inspired) wrapping this runtime.

## Do not

- Commit ISO, extracted FS, generated C/module binaries, or saves.
- Claim full decompilation or complete playability yet.


## Input notes

- ModernGekko user config: `~/.local/share/moderngekko/Config/`
- `GCPadNew.ini` keyboard map present (A=`X`, Start=Return, WASD, arrows, Q/E).
- `Dolphin.ini` has `BackgroundInput = True` for automation experiments.
- Reliable automated skip-to-file-select is still open; prefer a physical GameController next.
