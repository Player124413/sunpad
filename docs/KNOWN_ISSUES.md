# Known Issues

Last updated: 2026-08-05

## Blockers

1. **Stage 1 recompilation not yet proven.** Tools are checked out and the compiler check passes, but Sunshine has not yet been extracted/recompiled/launched successfully in this workspace.
2. **No published ReShine source.** Sunshine-specific private patches, if any, are not available for direct reuse.

## Non-blocking observations

- ModernGekko-Template’s `lib/` symlinks must resolve to sibling `ref/ModernGekko` and `ref/DolRecomp` checkouts (relative path `../../...` from the template directory).
- ModernGekko requires substantial dolphin Externals before a full runtime build.
- Matching decompilation (`doldecomp/sms`) is incomplete and not the product runtime.
- Controller configuration in ModernGekko is file-based (`GCPadNew.ini`), not an in-app UI.
