# Architecture

Last updated: 2026-08-05

## Goal architecture

```text
User-owned GMSE01 disc image
        │
        ▼
  DolRecomp extract + AOT recompile
        │
        ▼
 Local generated host module (gitignored)
        │
        ▼
 ModernGekko / shared GameCube compatibility runtime
        │
        ├── macOS app shell (Stage 2)
        ├── iOS app shell (Stage 4)
        └── iPadOS app shell (Stage 4)
```

## Planned repository layout

```text
sunpad/
  docs/                 first-class documentation
  scripts/              reproducible build/test helpers
  patches/              SunPad-owned patches (generic vs Sunshine-specific)
  src/
    runtime/            shared GameCube runtime adaptations
    apple/              shared Apple platform layer
    macos/              macOS application (future)
    ios/                iOS/iPadOS application (future)
  tests/
  artifacts/            local logs/screenshots (gitignored contents)
  ref/                  external clones + local disc (mostly untracked/local)
```

## Separation rules

1. **Generated recomp output** never enters Git.
2. **Sunshine-specific fixes** live in clearly named patch/docs areas, not hidden inside generic Apple UI code.
3. **Shared runtime** is separate from platform lifecycle/UI.
4. **BellPad** is a pattern reference, not a code base to fork wholesale for Animal Crossing logic.

## CPU execution model

- Preferred: AOT statically recompiled guest code module.
- Allowed: Dolphin-derived compatibility services for hardware/OS.
- Forbidden for product path: runtime PowerPC JIT on Apple platforms.

## Stage-specific notes

### Stage 1
Desktop reproduction using upstream ModernGekko-Template with local ISO.

### Stage 2
Wrap/replace the launcher with a polished native macOS app experience inspired by BellPad menus/controllers while still using AOT module + compatibility runtime.

### Stage 3
Audit and remove desktop-only assumptions that break iOS/iPadOS (dynamic module policy, paths, window system, executable memory, OpenGL-only paths). Prefer static link of generated code or another App Store-compatible AOT strategy.

### Stage 4
Shared runtime + Metal + GameController + Sunshine-specific touch controls.
