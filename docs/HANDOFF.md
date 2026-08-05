# Handoff

Last updated: 2026-08-05

## One-screen summary

SunPad is at the beginning of Stage 1. Local Sunshine USA (`GMSE01` Rev0) is present and hashed. Public recomp tooling is cloned and pinned. Template toolchain check passes. No playable recompilation run has been completed yet. There is no public ReShine repository to copy; reproduce via DolRecomp + ModernGekko.

## Exact current tree state

- Root scaffold exists: docs, scripts, src, patches, tests, artifacts, `.gitignore`.
- `ref/Super Mario Sunshine.iso` = GMSE01 Rev0, SHA-256 `67cec163...e51d`.
- Clones: ModernGekko, ModernGekko-Template, DolRecomp, RecompCore, sms, StrikersRecomp, bellpad.
- ModernGekko `vendor/dolphin` checked out to `e13ab348f13cd67879f6db6e9d7185410f8f62c6`.
- Essential dolphin Externals submodules initialized (SDL, zlib-ng, libspng, VMA, cubeb, SPIRV-Cross, libusb).
- Template `lib/` symlinks and `iso/Super Mario Sunshine.iso` symlink created.
- `make check FETCH=0` succeeded.

## What works

- Research + dependency pinning documentation.
- Host compiler/tool validation for the template.

## What does not work

- Full tools build not yet completed in this handoff snapshot.
- No extract/recompile/run evidence for Sunshine yet.
- No SunPad app targets.

## How to resume immediately

```sh
cd /Users/chrissotraidis/GitHub/sunpad
# verify disc
file "ref/Super Mario Sunshine.iso"
cd ref/ModernGekko-Template
ls -la lib iso
make check FETCH=0
make tools
make extract ISO="../../Super Mario Sunshine.iso"
make recompile GAME=Super-Mario-Sunshine
make run GAME=Super-Mario-Sunshine
```

Capture all logs under `artifacts/runtime/` and update STATUS/TESTING/HANDOFF after each milestone.

## Next actions in order

1. Finish `make tools` and fix any missing Externals/CMake options.
2. Extract and recompile GMSE01; record unknown instruction count.
3. Launch and identify first boot failure with logs.
4. Implement minimal Sunshine-specific fixes only as needed.
5. Only after playable desktop proof, start macOS app shell (Stage 2).

## Do not do

- Do not commit the ISO, extracted FS, generated C/module binaries, or saves.
- Do not claim full decompilation.
- Do not skip to iOS before the macOS playable gate.


## Update: Stage 1 mid-flight evidence

- Extract + DolRecomp C generation succeeded with **zero unknown opcodes**.
- ModernGekko arm64 tools are built.
- Host module compile for `gGMSE01_recomp.dylib` is running and is the next gate before launch.
- Resume by checking:
  ```sh
  ./scripts/stage1-status.sh
  tail -20 artifacts/runtime/2026-08-05-port-build.log
  ```
- When the dylib exists:
  ```sh
  cd ref/ModernGekko-Template
  ./lib/ModernGekko/build/moderngekko-port run extracted/Super-Mario-Sunshine --backend c --toolchain clang --output build/modules
  ```
