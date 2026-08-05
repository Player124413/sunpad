# Testing

Last updated: 2026-08-05

## Principles

- Compilation success is not gameplay success.
- Capture dated evidence: target, OS, build config, git revision, game version, commands, logs, screenshots, result, remaining defects.
- Run only one iOS Simulator at a time in later stages.

## Game under test

- Disc: Super Mario Sunshine USA
- ID: `GMSE01` Rev 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## Stage 1 checklist

| Check | Status | Evidence |
|---|---|---|
| Disc identity/hash | Pass | `file` + Python header/hash on local ISO |
| Toolchain check | Pass | `make check` AppleClang 21 arm64 |
| Build DolRecomp/ModernGekko | Pass | arm64 moderngekko-port/run + dolrecomp |
| Extract disc | Pass | dolrecomp extract GMSE01 |
| Recompile main.dol, 0 unknown ops | Pass | 0 unknown; 221 chunks; see recompile log |
| Build host module | In progress | moderngekko-port compiling gGMSE01_recomp |
| Launch runtime | Pending | |
| Title screen | Pending | |
| Controller input | Pending | |
| Load playable area | Pending | |
| Complete objective | Pending | |
| Save/reload | Pending | |
| Extended session | Pending | |

## Evidence directory

Local runtime logs and screenshots should go under `artifacts/` (gitignored contents). Summaries belong in this file and [STATUS.md](STATUS.md).
