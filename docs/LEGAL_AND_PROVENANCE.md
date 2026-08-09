# Legal and Provenance

Last updated: 2026-08-09

## Project license

SunPad's original source and integration work is licensed under
[GNU GPL version 3 or later](../LICENSE). Distributed source and binaries must
also comply with the licenses and notice requirements of incorporated upstream
components. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and
[DEPENDENCIES.md](DEPENDENCIES.md). A dependency's own license and copyright
remain in force; the SunPad license does not replace them.

## Non-goals

SunPad will not:

- Redistribute Super Mario Sunshine or any Nintendo copyrighted assets.
- Commit disc images, extracted filesystems, textures, audio, or generated game-derived modules.
- Claim affiliation with or endorsement by Nintendo.
- Misrepresent static recompilation as a complete clean-room rewrite if Dolphin-derived runtime services remain.

## User-supplied game data

Users must provide their own legally obtained Super Mario Sunshine disc image. The current local development target is:

- Game ID: `GMSE01`
- Region: USA
- Revision: 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## Third-party open-source components

See [DEPENDENCIES.md](DEPENDENCIES.md). Major runtime/recompiler components are
GPL/Dolphin-derived and impose corresponding source, license, notice, and other
obligations on distributed binaries that incorporate them. An eventual IPA or
other binary release needs a separate artifact-level compliance audit; the
current repository documents a local source/developer workflow only.

## Provenance of research claims

- “ReShine” is referenced only as community-reported evidence via ModernGekko credits; no public Sunshine ReShine tree was located at research time.
- Matching decompilation progress is tracked separately from SunPad’s static-recompilation product path.
