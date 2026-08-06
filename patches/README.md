# Patches

SunPad-owned patches, kept separate from generic upstream tooling:

- **Generic runtime patches** — fixes to the Dolphin/ModernGekko-derived
  compatibility runtime that are not game-specific.
- **Sunshine-specific patches** — address maps, runtime code-patching ranges,
  HLE decisions, MMIO routing, or version-specific fixes required for
  `GMSE01`. These must be documented separately from generic changes and never
  hidden inside unrelated platform code.

Currently no patch files are applied: the unmodified public pipeline
(DolRecomp → ModernGekko) reproduces the title/intro, and Sunshine-specific
deltas will land here if the Stage 1 plaza/objective gates require them. See
[docs/RESEARCH.md](../docs/RESEARCH.md) and
[docs/DEPENDENCIES.md](../docs/DEPENDENCIES.md).
