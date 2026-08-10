# Install the developer-preview IPA

SunPad 0.1.0 Preview 1 is an unsigned arm64 IPA for iPhone and iPad. It must
be re-signed with your own Apple identity before installation.

1. Download `SunPad-0.1.0-preview.1-unsigned.ipa` from the GitHub release.
2. Verify its SHA-256 against the checksum on the release page.
3. Re-sign the IPA with a sideloading workflow you trust, making sure the
   nested `gGMSE01_recomp.dylib` is signed along with the app.
4. Install it, open **••• → Game Data & Saves → Change or Reimport**, and
   select your own legally obtained `GMSE01` USA revision 0 ISO/GCM image.

The IPA contains the open-source SunPad/ModernGekko runtime and its required
GMSE01 ahead-of-time recompiled executable module. It contains no disc image,
extracted game assets, save, settings, certificate, or provisioning profile.
It is not an App Store, TestFlight, or computer-free installation release.
