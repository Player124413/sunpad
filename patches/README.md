# Patches

SunPad-owned patches, kept separate from generic upstream tooling:

- **Generic runtime patches** — fixes to the Dolphin/ModernGekko-derived
  compatibility runtime that are not game-specific.
- **Sunshine-specific patches** — address maps, runtime code-patching ranges,
  HLE decisions, MMIO routing, or version-specific fixes required for
  `GMSE01`. These must be documented separately from generic changes and never
  hidden inside unrelated platform code.

## Applied patches

`ModernGekko-dolphin/` holds the SunPad-owned deltas against the vendored
Dolphin (`ref/ModernGekko/vendor/dolphin`). They are generic runtime patches,
not Sunshine-specific:

- `0001-staticrecomp-timebase-rate-and-tl-tu-read.patch` — the full
  StaticRecomp-core delta. The substantive 2026-08-08 fixes: advance the guest
  timebase at TB rate (CPU cycles / `SystemTimers::TIMER_RATIO`) from a
  SyncIn snapshot instead of 1 tick per CPU cycle (the old behavior ran guest
  `mftb` 12× fast inside native bursts and snapped it backwards at every
  burst boundary); materialize live `SPR_TL`/`SPR_TU` in `HookSPRRead`; add
  the `STATICRECOMP_NO_FALLBACK_JIT` env toggle so desktop can reproduce the
  iOS execution contract (module + interpreter, no fallback JIT). Also
  includes the pre-existing iOS no-JIT guard.
- `0002-ios-no-opengl-backend.patch` — do not define `HAS_OPENGL` for iOS
  builds (Metal-only there); without this the merged core archive fails to
  link (`vtable for OGL::VideoBackend`).

Apply from `ref/ModernGekko/vendor/dolphin` with
`git apply --unidiff-zero <patch>`. Other local vendor changes
(CoreAudio/AudioQueue backends, Mixer iOS behavior, platform stubs) predate
these patches and remain local; they are not yet represented by patch files.

See [docs/RESEARCH.md](../docs/RESEARCH.md) and
[docs/DEPENDENCIES.md](../docs/DEPENDENCIES.md).
