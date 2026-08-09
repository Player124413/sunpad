# Third-party notices

SunPad's own integration source is licensed under the GNU General Public
License, version 3 or later. The project builds against separately cloned,
pinned upstream repositories; their source and license files remain in those
checkouts and are not vendored into this repository.

| Component | Pin | License / notice |
|---|---|---|
| ModernGekko | `048c426ba3db0369e40826d22ad3adcce7fe7c58` | GPL-3.0-or-later |
| ModernGekko vendored Dolphin/RecompCore | `e13ab348f13cd67879f6db6e9d7185410f8f62c6` | Dolphin aggregate is GPLv3-compatible; per-file SPDX terms apply |
| DolRecomp | `48c4ef11dd59c7367a3479a433e39a35bda80695` | GPL-3.0 |
| ModernGekko-Template | `1ee85bb5e09c38f493a09f5fa6e9dc8228b23e42` | Build template; its dependencies retain their upstream licenses |

See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for URLs, purposes, and the
complete dependency inventory. A distributed binary that incorporates the
GPL-covered runtime must be accompanied by the corresponding source and the
applicable license notices as required by those licenses.

Super Mario Sunshine, Nintendo, and GameCube names, game imagery, and
screenshots are owned by their respective rights holders. They are not
licensed under the GPL and are used here only to identify compatibility and
document runtime behavior. No retail image, extracted asset, generated
game-derived module, or save is included.

The SunPad icon is a project-specific AI-generated image. Its provenance is
recorded beside the asset in
[`apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md`](apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).
