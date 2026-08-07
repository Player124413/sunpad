# Physical-iPad Audio Investigation

Last updated: 2026-08-07

## Status

Super Mario Sunshine boots and renders on a physical iPad, but its game-engine
audio is not correct. This remains an unresolved release blocker. The problem
is reproducible with the supported GMSE01 USA Rev 0 image and is not reproduced
when that same image runs in stock Dolphin 2606 on the same Mac.

This document records the observed behavior and the evidence gathered so that
future work starts from the signal path rather than repeatedly tuning the iOS
output buffer.

## Player-visible behavior

- The opening THP videos generally play their audio.
- Game-engine sounds begin, then are cut short or become silent.
- Mario's spoken "Super Mario Sunshine" title call is missing or truncated.
- The title-screen music and file-select music are absent or incomplete.
- Some short effects remain audible, which can make the failure sound like an
  output underrun even though the missing samples occur earlier in the pipeline.

## What the captures establish

The physical-device build and stock Dolphin were run with the same image and
their raw Dolphin DSP output was captured before the Apple output backend.
Both captures are 32,028 Hz stereo.

| Sample | Stock Dolphin duration | SunPad duration |
|---|---:|---:|
| Engine sound 1 | 0.919 s | 0.051 s |
| Engine sound 2 | 0.822 s | 0.053 s |
| Engine sound 3 | 0.504 s | 0.039 s |

For the first roughly 45 ms, corresponding signals correlate at 0.95-0.96.
The SunPad capture then becomes zero while stock Dolphin continues. This puts
the primary failure upstream of AVAudioSession, RemoteIO/AVAudioEngine, sample
rate conversion, and the iPad speaker.

Sunshine's JAudio path uses 560-sample frames at approximately 32,028.5 Hz:

```text
560 / 32028.5 = 17.48 ms per frame
3 buffers = 52.45 ms
```

That three-buffer duration closely matches the observed cutoff. The evidence
therefore points to the emulated JAudio/DSP producer ceasing to advance after
its initial buffers, rather than the Apple output consumer starving a healthy
audio stream.

## Why video audio can still work

THP movie audio follows a different route. It is decoded by the emulated CPU
and mixed through an external callback after `JASDSPBuf::mixDSP`. The title,
menu, voice, and effect paths depend on the normal JAudio/DSP frame and
interrupt sequence. Successful movie audio therefore does not prove that the
DSP scheduler is healthy.

## Investigated and not sufficient

The following changes did not restore complete title/menu music or voices:

- activating an iOS playback `AVAudioSession`;
- increasing the Dolphin audio buffer and enabling gap filling;
- replacing the initial Apple output path with a 48 kHz RemoteIO path;
- booting from the retained ISO instead of relying only on extracted files;
- rebuilding and reinjecting the matching GMSE01 native module;
- verifying the same ISO has complete audio in stock Dolphin;
- forcing Sunshine's `OSDisableInterrupts`, `OSEnableInterrupts`, and
  `OSRestoreInterrupts` range (`0x803458AC-0x803458F8`) through Dolphin's
  interpreter.

The targeted interrupt fallback was a diagnostic experiment, not a fix, and
is not enabled in the checked-in app configuration.

## Leading area for future work

The strongest remaining lead is the static recompiler's CPU/timing contract,
especially interrupt delivery around `mtmsr` and the DSP frame-mail callbacks.
Stock Dolphin ends the translated block and checks pending external exceptions
when `mtmsr` changes interrupt state. The generated static code updates `msr`
inline, while the static core normally observes external interrupts at timing
slice boundaries.

That mismatch is consistent with the JAudio producer stopping after its
initial triple buffer, but the narrow interpreter-range experiment did not fix
the hardware behavior. A durable correction should therefore be proven with
instrumentation at these boundaries before changing more output code:

1. AID `syncAudio` message delivery and `updateDac` cadence.
2. DSP frame-mail delivery, seven subframe updates, and `finishDSPFrame`.
3. Pending external exception state immediately before and after every
   generated `mtmsr`.
4. DSP ring-buffer write position versus the mixer read position.

The next successful investigation should produce a continuous pre-output DSP
dump matching stock Dolphin before it is described as an iOS audio fix.

## Evidence boundary

The WAV captures, retail image, extracted game data, generated module, device
container, and device console logs are local and intentionally gitignored.
This repository contains only the findings and the source-side integration;
it does not contain Nintendo data or generated game-derived binaries.
