# Tests

SunPad treats runtime evidence as the source of truth: a successful compile is
not gameplay success. Dated checklists, commands, screenshots, and remaining
defects live in [docs/TESTING.md](../docs/TESTING.md), and the harness scripts
live in [scripts/](../scripts):

- `scripts/ios-build-core.sh` / `ios-provision.sh` — iOS core + module build
  and app provisioning.
- `scripts/gcpipe.py` — pipe-device input probes (PRESS/RELEASE, stick sets).
- `scripts/simdrag.swift` — posts real drags to the iOS Simulator for
  touch-control verification.
- `scripts/stage1-status.sh` / `stage1-run.sh` / `sunpad-capture.py` —
  desktop Stage 1 checks and capture helpers.

Run only one Simulator at a time on a given machine.
