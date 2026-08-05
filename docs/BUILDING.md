# Building

Last updated: 2026-08-05

## Prerequisites

Apple Silicon Mac with:

- Xcode 26.x + command-line tools
- Homebrew packages: `cmake`, `ninja`, `pkg-config`, `git`
- Python 3
- A legally obtained Super Mario Sunshine USA ISO (`GMSE01`)

## Stage 1: ModernGekko-Template reproduction

```sh
# from repository root
cd ref/ModernGekko-Template
# lib/ModernGekko and lib/DolRecomp should point at sibling clones
make check FETCH=0
make tools
make extract ISO="../../Super Mario Sunshine.iso"
make recompile GAME=Super-Mario-Sunshine
# later:
# make run GAME=Super-Mario-Sunshine
```

Notes:

- Generated/extracted output stays under `ref/ModernGekko-Template/extracted/` and local module caches; do not commit it.
- Controller input may require a Dolphin-style `GCPadNew.ini` in ModernGekko’s user config directory.

## Product builds (future stages)

macOS/iOS/iPadOS product commands will be added after Stage 1 proves a runnable recompilation path.
