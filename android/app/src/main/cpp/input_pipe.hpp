// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

// SunPad Android input pipe: encodes one normalized GameCube snapshot into
// Dolphin's pipe-device command stream (port of the Apple shared
// SunPadInputPipeEncoder) and manages the user-directory FIFO.

#pragma once

#include <cstdint>
#include <string>

namespace sunpad {

// Normalized GameCube state matching apple/shared/SunPadInputState.h:
// sticks [-127, 127], triggers [0, 255], buttons BellPad-compatible bits.
struct InputState {
  int8_t stickX = 0;
  int8_t stickY = 0;
  int8_t cStickX = 0;
  int8_t cStickY = 0;
  uint8_t triggerL = 0;
  uint8_t triggerR = 0;
  uint16_t buttons = 0;
};

enum : uint16_t {
  kButtonDpadLeft = 1 << 0,
  kButtonDpadRight = 1 << 1,
  kButtonDpadDown = 1 << 2,
  kButtonDpadUp = 1 << 3,
  kButtonZ = 1 << 4,
  kButtonR = 1 << 5,
  kButtonL = 1 << 6,
  kButtonA = 1 << 8,
  kButtonB = 1 << 9,
  kButtonX = 1 << 10,
  kButtonY = 1 << 11,
  kButtonStart = 1 << 12,
};

// Encodes a complete input snapshot as pipe commands ("SET MAIN x y", "PRESS
// A", ...). Button transitions are relative to previousButtons. The modern
// C-stick option reverses only the horizontal axis.
std::string EncodePipeCommands(const InputState& input,
                               uint16_t previousButtons,
                               bool modernCStickHorizontal);

// Writes the GCPadNew.ini mapping the pipe device to GameCube controls.
// Mirrors the config the iOS app writes before the runtime boots.
std::string GCPadNewIniContents();

}  // namespace sunpad
