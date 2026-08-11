// SunPad Android app build. The ModernGekko / Dolphin-derived core is built
// separately by scripts/android-build-core.sh and linked into libsunpad.so
// through the generated core_libs.cmake (gitignored, host-local paths).
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
}
