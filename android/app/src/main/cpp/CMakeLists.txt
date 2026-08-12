cmake_minimum_required(VERSION 3.22)
project(sunpad_app C CXX)

# Explicit -std=c++2b: valid on both NDK clang 17 (NDK r26, which rejects
# -std=c++23) and clang 18+. The app code is C++20-compatible; the core
# headers it includes are too.
add_compile_options(-std=c++2b)

# Provisioned by scripts/android-build-core.sh (gitignored, host-local paths):
#   SUNPAD_CORE_LIBS          merged ModernGekko + Dolphin core archives
#   SUNPAD_CORE_INCLUDE_DIRS  ModernGekko / vendored Dolphin include roots
include(${CMAKE_CURRENT_SOURCE_DIR}/generated/core_libs.cmake)
if(NOT DEFINED SUNPAD_CORE_LIBS OR NOT DEFINED SUNPAD_CORE_INCLUDE_DIRS)
    message(FATAL_ERROR
        "core libraries not provisioned; run scripts/android-build-core.sh first")
endif()

add_library(sunpad SHARED
    jni_bridge.cpp
    runtime_host.cpp
    input_pipe.cpp
)

target_include_directories(sunpad PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${SUNPAD_CORE_INCLUDE_DIRS}
)

target_link_libraries(sunpad PRIVATE
    android
    log
    OpenSLES
    # EGL/GLESv3: the core's GLContext (EGL backend) and the OGL video
    # backend reference these; the NDK sysroot provides them.
    EGL
    GLESv3
    ${SUNPAD_CORE_LIBS}
)
