# Architecture

Last updated: 2026-08-11

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
        ├── macOS app bundle (launcher + runner)
        ├── iOS app shell (SunPad.xcodeproj)
        ├── iPadOS app shell (same universal target)
        └── Android app shell (android/, port scaffold)
```

## Repository layout

```text
sunpad/
  docs/                 first-class documentation
  scripts/              build/test helpers (iOS toolchain, core build, provisioning)
  patches/              Complete reviewed snapshots for the ignored upstream trees
  apple/
    shared/             SunPadSettings, SunPadInputState (macOS+iOS)
    ios/                UIKit app, game overlay, core host, Xcode assets
    macos/              macOS bundle metadata, wrapper, and keyboard defaults
  android/              Android app shell (Kotlin + JNI shim; see docs/ANDROID.md)
  SunPad.xcodeproj      universal iPhone/iPad target
  ref/                  external clones + local disc (gitignored wholesale; see docs/DEPENDENCIES.md)
  tests/                test index and harness pointers (see docs/TESTING.md)
  artifacts/            local logs/screenshots (gitignored contents)
```

## CPU execution model

- Preferred: AOT statically recompiled guest code module (DolRecomp C →
  host-native module).
- Allowed: Dolphin-derived compatibility services for hardware/OS.
- Forbidden on Apple platforms: runtime PowerPC JIT. On iOS the static-recomp
  fallback uses the interpreter, and the generic software vertex loader
  replaces Dolphin's ARM64 code-generating loader.

## iOS host layering

```text
SunPadGameViewController
  ├── SunPadMetalSurfaceView (CAMetalLayer)
  │     └── Dolphin Metal backend renders here
  ├── SunPadCoreHost (background game thread)
  │     ├── moderngekko::Runtime (RuntimeConfig.render_surface = layer)
  │     └── pipe input bridge → Dolphin Pipes device
  └── SunPadGameOverlay (three-dot menu, render scale, touch controls)
        └── SunPadInputState (touch + GameController merged)
```

## Android host layering (port scaffold)

```text
SunPadActivity
  ├── SurfaceView ──> ANativeWindow ──> Dolphin Vulkan backend
  ├── TouchControlsView (BellPad-style overlay) + GamepadReader
  ├── GameInputState merge → ~60 Hz Choreographer → pipe encoder → Pipes device
  ├── GameDataImporter (SAF copy → validate → DiscIO extract → activate)
  └── libsunpad.so
        ├── jni_bridge.cpp      JNI exports, JavaVM registration, extraction
        ├── runtime_host.cpp    game thread + moderngekko::Runtime host
        └── merged core archives (PlatformAndroid, Vulkan, OpenSL ES, Pipes)
```

The Android runtime deltas live in the 0002 patch snapshots; see
[docs/ANDROID.md](ANDROID.md) for the mapping of each delta to upstream
interfaces.

## Separation rules

1. Generated recomp output never enters Git (`ref/**/generated/`, modules,
   `apple/ios/Provisioned/`).
2. Sunshine-specific fixes live in clearly named patch/docs areas.
3. Shared runtime is separate from platform lifecycle/UI.
4. BellPad is a pattern reference, not a fork source.

## iOS port deltas (recreated under ref/ModernGekko)

The ignored upstream trees are recreated from their pinned commits by
`scripts/bootstrap-dependencies.sh`; every required delta is represented by
the two complete snapshots indexed in [patches/README.md](../patches/README.md).

- `PlatformIOS.mm` (CAMetalLayer platform), Metal backend AppKit guards,
  cubeb/libusb/hidapi/Quartz/watcher/AGL gating, GCAdapter + FilesystemWatcher
  stubs, JIT fallback off, software vertex loader, translocated-path guard.
