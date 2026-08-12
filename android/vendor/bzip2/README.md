# bzip2 (vendored, for the Android build)

Static bzip2 1.0.x sources (BSD-style license, see LICENSE) pinned at the
upstream revision the vendored Dolphin expects
(6a8690fc8d26c815e798c588f796eabe9d684cf0, https://gitlab.com/bzip2/bzip2).

Why vendored: the Dolphin submodule `Externals/bzip2/bzip2` has no CMake
build file, and the Ubuntu `libbz2-dev` package only provides an x86_64
archive, which cannot be linked into the arm64 `libsunpad.so`.
`scripts/android-build-core.sh` compiles these sources with the NDK
toolchain into a static `libbz2.a` for arm64.
