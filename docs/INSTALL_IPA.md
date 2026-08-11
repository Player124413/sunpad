# Install the developer-preview IPA

SunPad 0.1.0 Preview 1 is an unsigned arm64 IPA for iPhone and iPad. It must
be re-signed with your own Apple identity before installation.

1. Download
   [`SunPad-0.1.0-preview.1-unsigned.ipa`](https://github.com/chrissotraidis/sunpad/releases/download/v0.1.0-preview.1/SunPad-0.1.0-preview.1-unsigned.ipa)
   from the [Preview 1 release](https://github.com/chrissotraidis/sunpad/releases/tag/v0.1.0-preview.1).
2. Verify SHA-256
   `4fdfe130eb3669dc3d7f5e3e5925041378905cacb11ac708dafc080cb40a8ebb`.
3. Re-sign the IPA with a sideloading workflow you trust, making sure the
   nested `gGMSE01_recomp.dylib` is signed along with the app.
4. Install it, open **••• → Game Data & Saves → Change or Reimport**, and
   select your own legally obtained `GMSE01` USA revision 0 ISO/GCM image.

The IPA contains the open-source SunPad/ModernGekko runtime and its required
GMSE01 ahead-of-time recompiled executable module. It contains no disc image,
extracted game assets, save, settings, certificate, or provisioning profile.
It is not an App Store, TestFlight, or computer-free installation release.

## LiveContainer status

LiveContainer is not currently a supported or verified SunPad launch path. One
user reports that Preview 1 does not work there, but no actionable environment,
signature, or log evidence has been collected. The supported preview workflow
remains re-signing both Mach-O files and installing the IPA normally.

For a useful LiveContainer investigation, record:

- exact IPA filename and SHA-256;
- LiveContainer version and download source;
- device model and OS version;
- signing and JIT settings;
- signature/identity output for both `SunPad.app/SunPad` and
  `SunPad.app/gGMSE01_recomp.dylib`;
- whether a window appears and the first visible error;
- LiveContainer launch output and a privacy-reviewed **••• → Share Diagnostic
  Log…** snapshot; and
- whether the same IPA works after a normal complete re-sign and installation.

Do not attach the game image, extracted game assets, saves, signing material,
or a device container. A LiveContainer launch failure does not by itself show
that the audited IPA or normal installation path is broken.
