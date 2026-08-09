# iOS and iPadOS

Last updated: 2026-08-08

## Current status

**Super Mario Sunshine (GMSE01) boots and renders on the iPhone 17 Pro and
iPad Pro 13-inch simulators (iOS 26.5)** through the SunPad app: the
ahead-of-time statically recompiled game module runs through the
ModernGekko/Dolphin-derived compatibility runtime, rendered by Dolphin's Metal
backend into a CAMetalLayer. Input advances the game. The on-device game-data
import flow is implemented and verified. A signed development build also boots
and renders on a physical iPad; game-engine audio is the major open defect.

## What is built

- `SunPad.xcodeproj` — universal iPhone/iPad target (device family 1,2),
  arm64, iOS 16.0+.
- `SunPadCoreHost` — boots the game on a background thread, owns the
  CAMetalLayer surface and the pipe-input bridge.
- `SunPadGameOverlay` — BellPad-inspired overlay: three-dot menu with render
  resolution (1× native/2×/3×/4×), aspect ratio (original 4:3 plus experimental
  16:9 and Fill Screen), touch-control settings (opacity, size,
  hide-on-controller, edit-layout, reset), Game Data & Saves actions.
- Sunshine touch controls: main stick, C-stick, A/B/X/Y/Z/Start/L/R.
- Shared settings (`SunPadSettings`) and normalized input
  (`SunPadInputState`) reused by macOS later.

## Runtime port (no JIT)

The ModernGekko core builds for the iOS Simulator via
`scripts/ios-simulator-toolchain.cmake` and `scripts/ios-build-core.sh`, and
for physical arm64 devices via `scripts/ios-device-toolchain.cmake` and
`scripts/ios-build-core-device.sh`.
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

The Apple audio output path receives data from the Dolphin Mixer, but physical
iPad testing found that the upstream JAudio/DSP stream truncates after its
initial buffers. THP video audio follows a separate CPU-mixed path and can
remain audible. See [AUDIO_ISSUE.md](AUDIO_ISSUE.md) before changing output
buffering again. The persisted 1×-4× render-resolution choice is applied live
through `Config::GFX_EFB_SCALE` (at boot and on change).
Aspect changes are applied through Dolphin's graphics config without resizing
the Metal surface or its separate UIKit touch overlay, so control placement is
unchanged. Original 4:3 is the default on iPhone and iPad.

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
- SunPad writes low-frequency boot, display, controller, lifecycle,
  memory-warning, input-pipe, and runtime-exit breadcrumbs to both the unified
  device log and `Library/Application Support/SunPad/Logs/runtime.log`. The
  persistent log rotates at 1 MB and survives relaunches. Retrieve it later
  without stopping the game:

  ```sh
  xcrun devicectl device copy from --device <device-id> \
    --domain-type appDataContainer \
    --domain-identifier com.sunpad.SunPad \
    --source "Library/Application Support/SunPad/Logs" \
    --destination /tmp/sunpad-app-logs
  ```

- While the runtime is booting, a visible startup message replaces the former
  unexplained black surface. It disappears after the first measured game
  frame.
- Development provisioning must use non-removing CoreDevice directory
  overlays. On the current iOS/Xcode combination,
  `--remove-existing-content true` cleared unrelated app-container data even
  when the requested destination was nested. Upload the temporary runtime
  module first, then overlay game data, saves, and configuration with
  `--remove-existing-content false`, and read every protected file back.
- `-sunpadRestorePreferences` is an explicit maintenance launch flag. When
  requested, the app imports `tmp/SunPadPreferencesRestore.plist` through
  `NSUserDefaults` and deletes the temporary payload. This avoids direct plist
  replacement being discarded by iOS's preferences daemon during a
  device-settings recovery.

## HDMI + wired-controller crash investigation (2026-08-09)

The iPad retained seven ordinary SunPad crash reports from the prior evening.
All seven are `SIGABRT` / `stack buffer overflow`, and every faulting stack is:

```text
SunPadCoreHost publishInput
SunPadGameViewController publishMergedInput
60 Hz input dispatch timer
```

The first affected session ran for hours and then crashed after the wired
controller was introduced. With the controller still attached, the following
relaunches crashed after roughly 8–30 seconds. The controller callback built a
complete input snapshot without initializing its button bitmask. Random button
edges could then make the pipe encoder append beyond its 128-byte stack buffer;
`snprintf` returned the full would-have-written length, so subsequent appends
used an out-of-bounds pointer and the stack protector aborted the app.

The mirrored HDMI display does not appear anywhere in the exception path and
is not needed to reproduce the defect. It may have made the relaunch look worse
because a connected controller hides the touch overlay, leaving only the black
Metal boot surface. External-display mode changes are now logged so a separate
display failure can be distinguished if one occurs later.
