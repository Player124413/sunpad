# Status

Last updated: 2026-08-05

Current phase: **Stage 1 — research and reproduce Super Mario Sunshine static recompilation** on Apple Silicon macOS.

## Confirmed local materials

- [ref/bellpad](../ref/bellpad): BellPad Animal Crossing Apple-platform reference (primary UX/integration pattern source). Nested git checkout of `https://github.com/chrissotraidis/bellpad.git`.
- [ref/Super Mario Sunshine.iso](../ref/Super%20Mario%20Sunshine.iso): local retail GameCube image, **not tracked by Git**.
  - Disc ID: `GMSE01`
  - Region: USA
  - Revision: 0
  - Title string: `Super Mario Sunshine`
  - Size: 1,459,978,240 bytes
  - SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`
- Public upstream clones under `ref/`:
  - ExpansionPak/ModernGekko
  - ExpansionPak/ModernGekko-Template
  - ExpansionPak/DolRecomp
  - ExpansionPak/RecompCore
  - doldecomp/sms
  - aharonahdoot/StrikersRecomp (adjacent worked example for the same toolchain family)

## Architecture stance (current)

SunPad targets **ahead-of-time static recompilation** of GameCube PowerPC CPU code via DolRecomp, executed through a Dolphin-derived **GameCube compatibility runtime** (ModernGekko / RecompCore lineage). This is **not** a claim that Super Mario Sunshine is fully decompiled, and it is **not** a pure high-level rewrite.

Precise wording for public docs:

> Ahead-of-time statically recompiled game CPU code running through a GameCube compatibility runtime.

## Stage gates

| Stage | Goal | Status |
|---|---|---|
| 1 | Reproduce Sunshine recompilation to playable desktop session | **In progress** |
| 2 | Native Apple Silicon macOS `.app` proof | Not started |
| 3 | Mobile-runtime hardening (no JIT / App Store-compatible AOT) | Not started |
| 4 | iPhone + iPad apps, touch controls, lifecycle | Not started |

## What works right now

- Repository scaffold: `docs/`, `src/`, `scripts/`, `patches/`, `tests/`, `artifacts/`, root `.gitignore`.
- Disc identity and hash recorded.
- Public toolchain repositories cloned and revision-pinned in [DEPENDENCIES.md](DEPENDENCIES.md).
- ModernGekko-Template wired to local ModernGekko + DolRecomp checkouts.
- `make check` succeeds on Apple Silicon with AppleClang 21 / CMake / Ninja.
- ModernGekko `vendor/dolphin` (RecompCore `moderngekko-vendor`) and essential Externals submodules initialized for macOS tooling.

## What does not work yet

- No successful Sunshine extract/recompile/module-build/run evidence yet.
- No title-screen, controller, Delfino Plaza, save/reload, or extended-session proof.
- No SunPad macOS/iOS application shell yet.
- No Sunshine-specific runtime fixes isolated yet (unknown whether generic upstream tools suffice).

## ReShine public evidence

No public repository named “ReShine” for Super Mario Sunshine was found in the current GitHub ecosystem search. ModernGekko’s README credits **binsento** for a Super Mario Sunshine recomp in the Hall of Fame, but the actual Sunshine project sources, patches, mappings, and runtime deltas are **not published** in the repositories inspected so far. SunPad therefore treats ReShine as a reported private/community achievement and attempts to reproduce the behavior from public DolRecomp + ModernGekko tooling plus local diagnostics.

## Next highest-priority task

1. Build DolRecomp + ModernGekko tools on this host.
2. Extract `GMSE01` with DolRecomp.
3. Recompile `main.dol` and record unknown-instruction count.
4. Compile the generated module and launch through `moderngekko-run`.
5. Capture boot logs and determine the first divergence/crash point.

See [HANDOFF.md](HANDOFF.md) for resume instructions.


## Stage 1 live progress

Recorded during 2026-08-05 Stage 1 reproduction:

1. **Disc verified**: GMSE01 Rev0, SHA-256 `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`.
2. **DolRecomp extract**: success to `ref/ModernGekko-Template/extracted/Super-Mario-Sunshine` (`sys/main.dol` present).
3. **main.dol recompile**:
   - text[0]: 2320 decoded, 0 unknown
   - text[1]: 898736 decoded, 0 unknown
   - total known instructions ≈ 899338 (+ embedded data)
   - 221 generated C chunks
   - warning: possible runtime self-modifying / patching ranges listed in `generated_smc.txt` (138 lines)
4. **ModernGekko tools**: `moderngekko-port` and `moderngekko-run` linked as Mach-O arm64.
5. **Module compile**: `gGMSE01_recomp` CMake build started via `moderngekko-port build` (221 chunks + runtime glue). In progress at last handoff update.
6. **Launch / title screen**: not yet attempted; blocked on module dylib completion.

Logs under `artifacts/runtime/` (local, gitignored contents).
