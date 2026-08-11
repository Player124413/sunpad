# SunPad Android app

Android shell for the SunPad Super Mario Sunshine static-recompilation port.
See [`docs/ANDROID.md`](../docs/ANDROID.md) in the repository root for the
full port document: runtime deltas, build steps, and current status.

Quick summary:

```sh
./scripts/android-build-core.sh   # NDK required; builds core + module, provisions app
cd android && ./gradlew :app:assembleDebug
```

A GitHub Actions workflow (`ci/android-build.yml`) builds the APK in CI —
see `docs/ANDROID.md` → "Building with GitHub Actions" for activation.

- The app targets `arm64-v8a`, Android 8.0 (API 26)+, renders with Vulkan
  into a `SurfaceView`, and plays audio through OpenSL ES.
- Game data and the recompiled game module are never bundled: both are
  imported on-device from the setup dialog (SAF document picker).
- This shell is a port scaffold: it awaits its first device/emulator
  acceptance run.
