# iOS and iPadOS

Last updated: 2026-08-06

## Current status

**Super Mario Sunshine (GMSE01) boots and renders on the iPhone 17 Pro and
iPad Pro 13-inch simulators (iOS 26.5)** through the SunPad app: the
ahead-of-time statically recompiled game module runs through the
ModernGekko/Dolphin-derived compatibility runtime, rendered by Dolphin's Metal
backend into a CAMetalLayer. Input advances the game. The on-device game-data
import flow is implemented and verified; physical-device verification remains.

## What is built

- `SunPad.xcodeproj` — universal iPhone/iPad target (device family 1,2),
  arm64, iOS 16.0+.
- `SunPadCoreHost` — boots the game on a background thread, owns the
  CAMetalLayer surface and the pipe-input bridge.
- `SunPadGameOverlay` — BellPad-inspired overlay: three-dot menu with render
  resolution (Native/1×/2×/3×/4×), touch-control settings (opacity, size,
  hide-on-controller, edit-layout, reset), Game Data & Saves actions.
- Sunshine touch controls: main stick, C-stick, A/B/X/Y/Z/Start/L/R.
- Shared settings (`SunPadSettings`) and normalized input
  (`SunPadInputState`) reused by macOS later.

## Runtime port (no JIT)

The ModernGekko core builds for the iOS Simulator via
`scripts/ios-simulator-toolchain.cmake` and `scripts/ios-build-core.sh`.
SunPad-specific iOS changes (all in `ref/ModernGekko`):

- `DolphinNoGUI/PlatformIOS.mm` — CAMetalLayer platform for the runtime.
- Metal backend: AppKit guarded by `TARGET_OS_OSX`; `setDisplaySyncEnabled:`
  macOS-only; HDR detection guarded.
- cubeb, libusb, hidapi, the macOS Quartz input backend, FSEvents watcher,
  and the AGL GL interface are disabled or stubbed on iOS.
- `GCAdapter_iOS.cpp` / `FilesystemWatcher_iOS.cpp` — linkable stubs.
- The static-recomp fallback JIT (`JitArm64`) is not created on iOS;
  un-recompiled regions use the interpreter. The ARM64 vertex loader is
  replaced by the generic software loader (`GFX_VERTEX_LOADER_TYPE=Software`).
- Translocated-path (macOS-only) bundle code is skipped on iOS.

Audio uses a native `AVAudioEngine` backend (`AudioEngineStream`) feeding the
Dolphin Mixer at 48 kHz, and the persisted Native/1×-4× render-resolution
choice is applied live through `Config::GFX_EFB_SCALE` (at boot and on change).

## Game data on mobile

The import flow is implemented and verified on the Simulator:

1. **Document picker** opens from "Game Data & Saves > Change or Reimport".
2. **Validate** the GameCube header (magic at 0x1C, GMSE01 game code at 0x00).
3. **Retain** a private copy in Application Support.
4. **Extract on-device** (`SunPadDiscExtractor`, Dolphin's DiscIO) into
   `SunPad/GameData/GMSE01` (`sys/` + `files/`).
5. **Boot** the extracted root with the provisioned module.

Verified: the on-device extraction produces the same 174-file tree as the
desktop extraction, and the game boots from the imported image and responds to
input. The recompiled module still comes from the Mac toolchain (iOS has no C
compiler); matching the provisioned module to the imported disc (game ID) is
the remaining gap. A `-sunpadImportTest <iso>` launch argument runs the flow
headlessly for verification.

## Lifecycle and controls

- App delegate pause/resume/background hooks exist but are stubs; save
  flushing before suspension is the next milestone.
- GameController polling merges into the same normalized input snapshot as
  touch; touch controls auto-hide when a controller is connected.
