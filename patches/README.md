# Patch Snapshots

SunPad carries two complete, reviewable snapshots of all required changes to
its ignored upstream trees:

| Patch | Applies to | Contents |
|---|---|---|
| `ModernGekko/0001-sunpad-apple-runtime.patch` | Pinned ModernGekko root | Apple frontend/runtime integration, macOS Metal defaults, iOS platform and build wiring, and the SunPad-owned files required by the Apple workflows |
| `ModernGekko-dolphin/0001-sunpad-ios-runtime.patch` | Pinned `ModernGekko/vendor/dolphin` | Complete Dolphin-derived iOS/runtime delta, including Metal/platform guards and stubs, no-JIT/software-loader behavior, iOS audio integration, StaticRecomp timebase/TL/TU fixes, and iOS backend/link fixes |

These replace the earlier partial patch series. Required CoreAudio,
mixer, platform-stub, frontend, and build changes are no longer
described as unrepresented local edits.

Do not apply these snapshots by hand to an arbitrary checkout. From the
repository root, run:

```sh
./scripts/bootstrap-dependencies.sh
```

The bootstrap script checks out the exact revisions recorded in
[DEPENDENCIES.md](../docs/DEPENDENCIES.md), verifies the vendored Dolphin
revision, and applies each patch once. It accepts a patch that is already
fully applied and stops if a checkout is on an unexpected commit or either
snapshot does not apply cleanly.

The snapshots contain generic Apple/runtime integration for SunPad's current
`GMSE01` development path. A future game-specific address map, runtime
code-patching range, HLE decision, MMIO route, or revision-specific workaround
must remain clearly identified and reviewed rather than hidden in an unrelated
platform edit.

See [RESEARCH.md](../docs/RESEARCH.md) and
[DEPENDENCIES.md](../docs/DEPENDENCIES.md) for architecture and provenance.
