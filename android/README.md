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
- Game data is never bundled. The recompiled module is either imported from
  the setup dialog or, for a workflow run with `iso_url` or `module_url`,
  bundled into the APK and extracted privately on first launch.
- This shell is a port scaffold: it awaits its first device/emulator
  acceptance run.
