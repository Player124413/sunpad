# Maintainer Notes

Last updated: 2026-08-09

This is a public maintainer summary, not a machine-specific handoff. SunPad is
an experimental source/developer workflow for `GMSE01` USA revision 0. It does
not publish a ready-to-install IPA or any game data.

## Reproduce the local inputs

From the repository root:

```sh
./scripts/bootstrap-dependencies.sh
./scripts/prepare-game.sh /path/to/GMSE01.iso
```

The first command recreates the ignored public dependency tree at exact
reviewed commits and applies the two complete SunPad patch snapshots. The
second verifies the supported image SHA-256, builds the desktop tools, extracts
the image locally, and produces the generated module inputs. Neither command
downloads or commits game data.

Build the desired development target after preparation:

```sh
# iOS Simulator core/module and Xcode provisioning
./scripts/ios-build-core.sh

# Physical iPhone/iPad core/module and Xcode provisioning
./scripts/ios-build-core-device.sh

# Local Apple Silicon app bundle
./scripts/package-macos-app.sh
```

The physical-device workflow also requires local signing and separate
provisioning of the locally generated module. See [BUILDING.md](BUILDING.md).
It is not IPA distribution packaging. Use an in-place install when preserving
device data, and never use a removing CoreDevice container overlay for updates.

## Current accepted evidence

- Simulator and physical iPad boot, Metal rendering, import/extraction, touch
  input, and gameplay have been demonstrated.
- The controller snapshot and input-pipe overflow crash is fixed in source and
  covered by a focused regression test; exact HDMI/controller replay remains.
- The guest-timebase audio defect is fixed and continuous audio is verified on
  desktop parity runs and the iOS Simulator. Physical-device audio
  re-acceptance remains.
- iPhone 14 boots but is slower than the iPad experience even at 1×. Recommend
  iPhone 15 Pro or newer for iPhone development testing.
- iOS 16.0 and macOS 14.0 are configured deployment targets. Fresh complete
  artifacts still need minimum-OS inspection and oldest-target runtime tests.

## Public-release gates still open

1. Build every target from a clean clone and run `./scripts/check-repository.sh`.
2. Inspect the minimum OS recorded in every final app, executable, static-input
   library where applicable, and generated module; then test the oldest claimed
   OS/hardware.
3. Re-run physical-device audio acceptance with the fixed core, including an
   audible title/voice/gameplay check.
4. Re-run the hardened mobile import, same-filename reimport, failed-import
   rollback, removal-with-save-preservation, and diagnostic-sharing flows.
5. Complete the exact HDMI + wired-controller replay and broader lifecycle,
   save/reload, performance, and extended-session checks.
6. Define and audit any eventual binary/IPA distribution separately. Generated
   game-derived modules, retail images, extracted files, saves, and signing
   material must remain local.

## Reporting

Record the git revision, target, OS/device, commands, game revision, observed
runtime behavior, and remaining gap in [TESTING.md](TESTING.md). Do not convert
configured or source-inspected behavior into a physical-acceptance claim.
