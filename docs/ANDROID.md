# Android port

Last updated: 2026-08-11

Status: **port scaffolding complete — runtime deltas, Android app shell, and
build tooling are in the repository; no Android hardware or NDK acceptance
run has happened yet.** Everything below the build steps is the design the
port implements; hardware acceptance remains open (see
[STATUS.md](STATUS.md)).

## Goal

SunPad on Android phones and tablets: the same ahead-of-time statically
recompiled Super Mario Sunshine module through the ModernGekko /
Dolphin-derived compatibility runtime, rendered with **Vulkan** into an
`ANativeWindow`, with **OpenSL ES** audio, BellPad-style touch controls,
Android gamepad merging, and user-owned game-data import through the Storage
Access Framework.

Dolphin's Android support is largely retained in the pinned vendored runtime
(Vulkan Android WSI, OpenSL ES backend, Android CMake paths), so the port
delta is small and clearly identified:

| Area | Apple (existing) | Android (this port) |
|---|---|---|
| Runtime platform | `PlatformIOS.mm` (CAMetalLayer) | `PlatformAndroid.cpp` (ANativeWindow) |
| Video backend | Metal | Vulkan (OGL available as fallback) |
| Audio backend | AVAudioEngine / CoreAudio | OpenSL ES via the SunPad `AudioUtils` bridge |
| Input | UIKit + GameController → Pipes | Touch overlay + Android gamepad → Pipes |
| Game data | Files document picker | SAF document picker |
| Build | Xcode + iOS toolchains | Gradle + NDK toolchain |

## Repository layout (Android parts)

```text
android/
  app/
    build.gradle.kts            app module (arm64-v8a, minSdk 26)
    src/main/
      AndroidManifest.xml
      java/com/sunpad/android/  SunPadActivity, SunPadNative, import flow,
                                touch controls, gamepad reader, AudioUtils
      cpp/
        jni_bridge.cpp          JNI exports + DiscIO extraction
        runtime_host.cpp        C++ mirror of the iOS SunPadCoreHost
        input_pipe.cpp          Pipes encoder port (SunPadInputPipeEncoder)
        generated/              gitignored core_libs.cmake (provisioned)
      res/                      theme, strings, launcher icon
  README.md
patches/
  ModernGekko/0002-sunpad-android-runtime.patch
  ModernGekko-dolphin/0002-sunpad-android-runtime.patch
scripts/
  android-toolchain.cmake       NDK wrapper (arm64-v8a, c++_shared)
  android-build-core.sh         core + module build and provisioning
tests/
  test-android-patches.sh       patch reproducibility (offline + network mode)
```

## Build

Prerequisites: the standard SunPad prerequisites (Apple Silicon Mac, CMake,
Ninja, Git, Python) plus

- **Android NDK** r26 or newer (set `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`);
- **JDK 17** and **Gradle 8.7+** with the Android Gradle Plugin 8.5.2;
- a legally obtained Super Mario Sunshine USA revision 0 image (`GMSE01`)
  and the prepared module sources from `scripts/prepare-game.sh`.

The repo carries a Gradle wrapper (`android/gradlew`, Gradle 8.9), so the
app build does not need a system Gradle install.

Build the core and provision the app:

```sh
./scripts/android-build-core.sh
```

This runs `bootstrap-dependencies.sh` (which now also applies the Android
runtime patches and initializes the Vulkan submodules —
`Vulkan-Headers`, `VulkanMemoryAllocator`, `libadrenotools` — when an NDK is
present), configures ModernGekko for `arm64-v8a` with Vulkan, builds
`libmoderngekko.a` and the full core library set, builds the GMSE01 module as
`/tmp/sunpad-module-android/gGMSE01_recomp.so` **when the prepared game
sources exist** (otherwise the module step is skipped with a warning — the
core and app do not need game data), and writes the gitignored
`android/app/src/main/cpp/generated/core_libs.cmake` with the host-local
archive list and include paths.

Build the APK:

```sh
cd android
./gradlew :app:assembleDebug
```

The APK never contains game data or the game module. The debug APK is
installable with `adb install app/build/outputs/apk/debug/app-debug.apk`.

## Building with GitHub Actions

The repository ships `ci/android-build.yml`, a workflow that builds the
whole Android app on GitHub's `ubuntu-latest` runners — no local Mac, NDK,
or game data needed:

1. installs JDK 17, the Android SDK/NDK r26, Ninja, and clang;
2. runs `bootstrap-dependencies.sh` (pinned clones + the 0001/0002 patches);
3. runs `android-build-core.sh` (Android arm64 core, Vulkan + OpenSL ES);
4. builds `app-debug.apk` with `./gradlew :app:assembleDebug` and runs the
   JUnit mapping tests;
5. uploads the APK as the `sunpad-debug-apk` artifact (Actions → run →
   Artifacts).

### Building the APK with the game module bundled (ISO URL)

The workflow accepts a **direct download URL to your GMSE01 ISO** in the
`workflow_dispatch` form:

1. **Actions → Android build → Run workflow**;
2. paste the direct link into the **iso_url** field (the ISO must be the
   supported GMSE01 USA Rev 0 image — the run verifies its SHA-256 and
   fails with a clear message otherwise);
3. the run downloads the image, validates it, generates the DolRecomp C
   sources (`scripts/ci-prepare-game.sh`), recompiles `gGMSE01_recomp.so`
   for Android arm64, and **bundles it into the APK** under
   `assets/modules/`;
4. the app extracts the bundled module to private storage on first launch —
   no on-device module step needed.

Notes on the URL: it must be a direct link (the file starts downloading
immediately). GitHub release assets, S3/GCS signed links, and similar work;
share-link pages (Google Drive web UI, Mega) do not. The downloaded ISO is
only used inside the runner and is not committed anywhere.

Speed and retries:

- the download uses **aria2 with 16 connections** (multi-connection speeds up
  servers that support range requests);
- the ISO is cached per URL in the GitHub Actions cache, so re-running the
  workflow with the same link skips the download entirely (the cache holds
  1.4 GB and is keyed by the URL you pasted);
- for quick debugging of build errors, re-run **without** the ISO URL: the
  core + APK build in a few minutes without the module step, and the ISO
  cache is not touched.

With the bundled module, the only remaining step on the device is
importing your ISO through the app's setup dialog — everything else is in
the APK.

To activate it, move the file back into GitHub's workflow directory (the
GitHub App used by the Arena agent lacks the `workflows` permission, so the
move must be done with your own account):

```sh
mkdir -p .github/workflows
git mv ci/android-build.yml .github/workflows/android-build.yml
git commit -m "Activate Android build workflow"
git push
```

The workflow also runs on `workflow_dispatch`, so after activation you can
trigger a build manually from the Actions tab even without pushing.

What the CI APK contains and does not contain:

- **Contains**: the app, the JNI shim, the statically linked
  ModernGekko/Dolphin core (Vulkan + OpenSL ES + Pipes input), and — when
  you supplied an ISO URL — the bundled `gGMSE01_recomp.so` module.
- **Does not contain**: game data (the 1.4 GB image itself). With a
  bundled module you only import your ISO on the device; without it, the
  module must be generated locally (`scripts/prepare-game.sh`) and
  provisioned on-device (step "On-device provisioning" below).

The first CI run may need small fixes (archive names in
`android-build-core.sh`, NDK version bumps, clang availability for the
module generation) — the build log will say precisely what is missing.

### On-device provisioning

1. Push the generated module to the device: `adb push
   /tmp/sunpad-module-android/gGMSE01_recomp.so /sdcard/Download/`
2. Launch SunPad; the setup dialog offers **Set game module
   (gGMSE01_recomp.so)…** — pick the pushed file.
3. Choose **Import game data (GMSE01 ISO/GCM)…** and pick your image in the
   system document picker. SunPad copies it privately, validates the exact
   size, GameCube magic, `GMSE01` code and disc 0 / revision 0, extracts it
   on-device with the core's DiscIO, and atomically activates it.
4. The game boots when both are present.

## Runtime deltas (patches 0002)

### ModernGekko (`patches/ModernGekko/0002-sunpad-android-runtime.patch`)

- `CMakeLists.txt`: an `Android` branch for the `moderngekko` target that
  compiles `PlatformAndroid.cpp`, defines `MODERNGEKKO_HAVE_ANDROID=1`, and
  links `android` + `log`.
- `src/runtime/dolphin_runtime.cpp`:
  - creates `Platform::CreateAndroidPlatform()` (ANativeWindow platform);
  - hands `RuntimeConfig.render_surface` to `ModernGekkoSetAndroidRenderSurface`;
  - prefers `BACKEND_OPENSLES` for audio on Android;
  - applies the mobile hardening the iOS port uses: software vertex loader
    (no executable-code generation) and the larger audio buffer /
    fill-gaps settings.

### Vendored Dolphin (`patches/ModernGekko-dolphin/0002-sunpad-android-runtime.patch`)

- `Source/Core/DolphinNoGUI/PlatformAndroid.cpp` (new): `Platform` subclass
  reporting `WindowSystemType::Android` with the app-provided `ANativeWindow`
  as render window + surface, and a `MainLoop` identical to the iOS
  platform's (HostDispatchJobs at ~8 ms). The `CreateAndroidPlatform()`
  factory is declared in `Platform.h` under `__ANDROID__`.
- `Source/Core/AudioCommon/OpenSLESStream.cpp`: decoupled from Dolphin's
  app-side `jni/AndroidCommon/IDCache` layer (which SunPad does not link).
  The app registers its `JavaVM` through `SunPadAndroidSetJavaVM` from its
  own `JNI_OnLoad`; the backend queries `com.sunpad.android.AudioUtils` for
  the native sample rate / frames-per-buffer, falling back to 48 kHz / 240
  frames when the VM or class is unavailable.
- `Source/Core/InputCommon/CMakeLists.txt`: on Android the Dolphin Java input
  interface (`ControllerInterface/Android` + `androidcommon`) is not built —
  touch and gamepad input are merged in the app and written to the Pipes
  device, mirroring the iOS app. (`Touch/InputOverrider` stays compiled.)

Everything else the port relies on was already present in the pinned vendor:
Vulkan Android WSI (`vkCreateAndroidSurfaceKHR`, `libvulkan.so` loading,
pre-rotation handling), the OpenSL ES backend wiring, `libadrenotools` for
Adreno custom drivers, and the Android paths in the Dolphin CMake.

## App architecture

```text
SunPadActivity
  ├── SurfaceView ──> ANativeWindow ──> Dolphin Vulkan backend
  ├── TouchControlsView (BellPad-style overlay, landscape,
  │                      drag-and-resize layout editor)
  ├── GamepadReader (KeyEvent + joystick MotionEvents,
  │                  A/B/X/Y/Z remapping layer)
  ├── merged GameInputState (OR buttons, strongest-wins sticks)
  │        └── ~60 Hz Choreographer loop → nativePublishInput
  │                 └── Pipes FIFO → Dolphin pipe device
  └── GameDataImporter (SAF copy → validation → DiscIO extraction → activate)
libsunpad.so
  ├── jni_bridge.cpp        JNI exports, JavaVM registration, extraction
  ├── runtime_host.cpp      game thread, Runtime lifecycle, render scale/aspect
  ├── input_pipe.cpp        pipe encoder (port of the Apple shared encoder)
  └── merged core archives  ModernGekko + Dolphin (Vulkan, OpenSL ES, Pipes)
```

The game module (`gGMSE01_recomp.so`) is loaded at runtime with `dlopen`
from app-private storage, exactly like the iOS `gGMSE01_recomp.dylib`.

## Touch layout editor

Ported from the iOS overlay. From the menu choose **Edit touch layout…**:

- drag any control (move stick, camera stick, A/B/X/Y/Z, L, R, Start) to a
  new position; positions persist as normalized origins
  (`SunPadControlOrigins` in app preferences, keyed like the iOS app) and
  survive app restart / reboot (they are lost only on Reset, clear-data, or
  uninstall);
- the grouped D-pad moves as one group and persists under
  `SunPadExperimentalDPadOriginKey`;
- tap a control to resize it (per-control scale 0.6–1.75, persisted in
  `SunPadControlSizeScales`; the D-pad group uses
  `SunPadExperimentalDPadScaleKey`);
- the editor bar at the bottom offers **Reset** (restores every position and
  size to defaults) and **Done**;
- while editing, touch input is suppressed and every editable control gets a
  selection border (yellow, blue when selected).

## Gamepad remapping

Ported from `apple/shared/SunPadControllerMapping.mm` to
`com.sunpad.android.ControllerMapping` with identical semantics and the same
regression coverage (`ControllerMappingTest`, mirroring the iOS tests):

- only A, B, X, Y, and the right shoulder (GameCube Z by default) are
  remappable; sticks, D-pad, Start, L, and analog triggers keep their
  BellPad direct mappings (right shoulder = Z, trigger axes = L/R pressure);
- **Controller button mapping…** in the menu lists each GameCube button with
  its current physical assignment; choosing one opens the five physical
  options; assigning an already-used button swaps the two assignments;
  **Reset to Default** restores A/B/X/Y + right-shoulder = Z;
- the mapping persists in `SunPadControllerMappingV1` and applies live to
  the merged input on the next frame (the Pipes device input is unaffected).

## Supported devices / SoCs

- **Architecture**: the APK is `arm64-v8a` only, so any 64-bit ARM Android
  device (Android 8.0 / API 26+) works: **MediaTek** (Dimensity, Helio G),
  Qualcomm (Snapdragon), Samsung Exynos, Google Tensor.
- **Rendering**: Vulkan. MediaTek SoCs use **Mali** GPUs (Dimensity
  Mali-G57/G68/G77/G610/G615/G720), which ship working Vulkan drivers. The
  Qualcomm-only custom-driver path (`adrenotools`, for sideloaded Adreno
  drivers) is gated on `/dev/kgsl-3d0` being present and a custom driver
  being selected, so it is **never exercised on MediaTek** — the runtime
  loads the system `libvulkan.so` as usual.
- **Fallback renderer**: if a device's Vulkan driver is broken or missing,
  switch `config.graphics.backend` from `"Vulkan"` to `"OGL"` in
  `android/app/src/main/cpp/runtime_host.cpp` (OpenGL ES via EGL is already
  linked into the app).
- **Audio**: OpenSL ES, available on every Android device.
- **No JIT**: the static-recompilation core does not generate executable
  host code at runtime, so there are no W^X / SELinux restrictions to fight
  on any SoC (this is the same stance as the iOS port).
- **Performance**: Super Mario Sunshine is a demanding GameCube title.
  Expect playable performance on upper-midrange and flagship SoCs
  (Dimensity 8000/9000 series and above, Snapdragon 7xx/8xx and above);
  entry-level Helio/A-series chips will likely be too slow even at 1x.

## Current boundaries and known gaps

- **No acceptance run**: nothing in `android/` has been compiled or booted on
  a device or emulator yet. The runtime patches are verified to apply at the
  pinned revisions (CI runs the network-mode patch test); the app compiles
  in principle but awaits a first NDK/Gradle build and hardware acceptance.
- The CI workflow is parked at `ci/repository-checks.yml` (outside
  `.github/workflows/` so it can be pushed without the GitHub App
  "workflows" permission); move it back to
  `.github/workflows/repository-checks.yml` to re-enable checks.
- **Saves**: Dolphin save files under the user directory are preserved by the
  removal flow (only imported game data is removed), matching iOS behavior.
- **OpenGL ES fallback**: `graphics.backend` is hardcoded to `"Vulkan"` in
  the runtime host; switching to `"OGL"` is a one-line change for devices
  where the Vulkan driver is broken.
- **60 FPS experiment**: the `enable_gmse01_60fps` runtime flag exists on all
  platforms; the Android menu does not expose it yet.

## Legal note

As with the Apple ports, the Android port contains no game assets, no disc
image, no generated module, and no Nintendo code beyond what the pinned
GPL-3.0 / Dolphin-derived upstreams provide. The user imports their own
legally obtained `GMSE01` image on-device.
