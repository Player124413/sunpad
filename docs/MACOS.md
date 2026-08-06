# macOS

Last updated: 2026-08-06

Stage 2 target: native Apple Silicon `SunPad.app`.

## Current status

Not started. Stage 1 desktop reproduction is proven through the title/intro
sequences (extract → recompile with 0 unknown ops → arm64 module →
`moderngekko-run` at ~30 FPS with Metal and pipe input); the remaining Stage 1
gates are plaza gameplay, objective completion, and save/reload evidence.
The native `SunPad.app` shell is built on top of the shared Apple runtime once
those gates close.

## Intended properties

- ARM64 process, no Rosetta, no PowerPC JIT product path
- Metal-preferred rendering through the compatibility runtime where available
- GameController + keyboard
- Memory-card save persistence
- Native menus inspired by BellPad
- Clear errors for missing/invalid game data
- Runtime/crash logs

## Gate criteria

See the Stage 2 checklist in the project goal / [STATUS.md](STATUS.md).
