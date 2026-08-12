# CMake toolchain for building ModernGekko's Dolphin-derived core for
# Android arm64-v8a. Product path has no JIT: the game CPU runs as a
# statically recompiled module through the compatibility runtime, and the
# portable software vertex loader replaces code-generating loaders.
#
# Requires the Android NDK. The NDK root is resolved in this order:
#   1. CMake variable ANDROID_NDK_HOME  (-DANDROID_NDK_HOME=<path>)
#   2. environment variable ANDROID_NDK_HOME
#   3. CMake variable ANDROID_NDK_ROOT  (-DANDROID_NDK_ROOT=<path>)
#   4. environment variable ANDROID_NDK_ROOT
# Environment variables must be read explicitly via $ENV{}: CMake does not
# import the process environment into CMake variables automatically, so an
# `export ANDROID_NDK_HOME=...` in the shell is invisible to `if(DEFINED
# ANDROID_NDK_HOME)`. The NDK's own android.toolchain.cmake does the heavy
# lifting once the root is resolved.
if(NOT DEFINED ANDROID_NDK_HOME OR ANDROID_NDK_HOME STREQUAL "")
  if(DEFINED ENV{ANDROID_NDK_HOME} AND NOT "$ENV{ANDROID_NDK_HOME}" STREQUAL "")
    set(ANDROID_NDK_HOME "$ENV{ANDROID_NDK_HOME}" CACHE PATH "Android NDK root")
  elseif(DEFINED ANDROID_NDK_ROOT AND NOT ANDROID_NDK_ROOT STREQUAL "")
    set(ANDROID_NDK_HOME "${ANDROID_NDK_ROOT}" CACHE PATH "Android NDK root")
  elseif(DEFINED ENV{ANDROID_NDK_ROOT} AND NOT "$ENV{ANDROID_NDK_ROOT}" STREQUAL "")
    set(ANDROID_NDK_HOME "$ENV{ANDROID_NDK_ROOT}" CACHE PATH "Android NDK root")
  endif()
endif()
if(NOT DEFINED ANDROID_NDK_HOME OR ANDROID_NDK_HOME STREQUAL "")
  message(FATAL_ERROR
    "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must point at the Android NDK "
    "(export it in the shell or pass -DANDROID_NDK_HOME=<path>)")
endif()

set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 26)               # matches the app minSdk
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK "${ANDROID_NDK_HOME}")
set(CMAKE_ANDROID_STL_TYPE c++_shared)

include("${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")
