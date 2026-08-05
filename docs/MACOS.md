# macOS

Last updated: 2026-08-05

Stage 2 target: native Apple Silicon `SunPad.app`.

## Current status

Not started. Waiting on Stage 1 recompilation reproduction.

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
