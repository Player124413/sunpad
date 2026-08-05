# Building

Last updated: 2026-08-05

## Prerequisites

Apple Silicon Mac with Xcode, CMake, Ninja, pkg-config, Git, Python 3, and a legally obtained Super Mario Sunshine USA ISO (`GMSE01`).

## Stage 1 reproduction (current proven path)

```sh
cd ref/ModernGekko-Template
# lib/ModernGekko -> ../../ModernGekko
# lib/DolRecomp -> ../../DolRecomp
make check FETCH=0

# Build tools (DolRecomp is quick; ModernGekko requires dolphin Externals)
# If ModernGekko configure fails, init missing vendor/dolphin Externals submodules.
cmake -S lib/ModernGekko -B lib/ModernGekko/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF \
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
ninja -C lib/ModernGekko/build moderngekko-port moderngekko-run -j8

# Extract + package module
./lib/DolRecomp/build/dolrecomp extract "../../Super Mario Sunshine.iso" extracted/Super-Mario-Sunshine
./lib/ModernGekko/build/moderngekko-port build extracted/Super-Mario-Sunshine \
  --backend c --toolchain clang --output build/modules

# Run
./lib/ModernGekko/build/moderngekko-run --game extracted/Super-Mario-Sunshine \
  --module "$(cat build/modules/GMSE01/active-module.txt)" --graphics Metal
```

Generated/extracted materials stay local and must not be committed.

## Product builds

macOS/iOS/iPadOS product commands will be added in Stages 2–4.
