# Known Issues

Last updated: 2026-08-05

## Open Stage 1 gaps

1. **Input path not fully proven.** Keyboard mapping and `BackgroundInput=True` are configured; scripted Start/A injection has not yet cleanly advanced from intro cutscenes into file-select/new-game with definitive before/after proof. Physical GameController is the next best probe.
2. **Playable hub / objective / save gates incomplete.**
3. **Verbose runtime logging is sparse** after module load; most evidence currently comes from window title + screenshots.
4. **SMC warning list present.** DolRecomp reported possible runtime code-patching ranges for GMSE01; no dedicated Sunshine patch set applied yet.

## Resolved / non-blocking observations

- ModernGekko first configure failed until dolphin Externals and vendored DolRecomp submodule were initialized.
- Module C compile is slow at `-O2` (221 ~1 MB chunks); first build took on the order of ~15 minutes on this machine.
- Early short launches that appeared to "exit immediately" were caused by aggressive process termination during automation, not by a hard boot crash; longer supervised runs held intro/title rendering.

## Product gaps (later stages)

- No SunPad-native menus, disc import UI, or iOS/iPad targets yet.
