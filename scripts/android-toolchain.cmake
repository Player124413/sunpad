# CMake toolchain for building ModernGekko's Dolphin-derived core for
# Android arm64-v8a. Product path has no JIT: the game CPU runs as a
# statically recompiled module through the compatibility runtime, and the
# portable software vertex loader replaces code-generating loaders.
#
# Requires the Android NDK. Set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) before
# configuring; the NDK's own android.toolchain.cmake does the heavy lifting.
if(NOT DEFINED ANDROID_NDK_HOME AND NOT DEFINED ANDROID_NDK_ROOT)
  message(FATAL_ERROR
    "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must point at the Android NDK")
endif()
if(NOT DEFINED ANDROID_NDK_HOME)
  set(ANDROID_NDK_HOME "${ANDROID_NDK_ROOT}" CACHE PATH "Android NDK root")
endif()

set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 26)               # matches the app minSdk
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK "${ANDROID_NDK_HOME}")
set(CMAKE_ANDROID_STL_TYPE c++_shared)

include("${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")
