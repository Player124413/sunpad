// Copyright 2026 SunPad project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "input_pipe.hpp"

#include <cstdio>

namespace sunpad {

std::string EncodePipeCommands(const InputState& input,
                               uint16_t previousButtons,
                               bool modernCStickHorizontal) {
  std::string commands;
  commands.reserve(320);
  auto append_command = [&commands](const char* format, auto... values) {
    char line[64];
    const int length = std::snprintf(line, sizeof(line), format, values...);
    if (length > 0 && static_cast<size_t>(length) < sizeof(line))
      commands.append(line, static_cast<size_t>(length));
  };

  // Sticks are int8 [-127,127]; the pipe expects raw [0,1] with 0.5 neutral
  // and the positive Y axis mapped to stick-down (GCPadNew.ini).
  const float mx = 0.5f + (input.stickX / 127.0f) * 0.5f;
  const float my = 0.5f - (input.stickY / 127.0f) * 0.5f;
  const float c_stick_x =
      modernCStickHorizontal ? -input.cStickX : input.cStickX;
  const float cx = 0.5f + (c_stick_x / 127.0f) * 0.5f;
  const float cy = 0.5f - (input.cStickY / 127.0f) * 0.5f;
  append_command("SET MAIN %.3f %.3f\n", mx, my);
  append_command("SET C %.3f %.3f\n", cx, cy);
  append_command("SET L %.3f\n", input.triggerL / 255.0f);
  append_command("SET R %.3f\n", input.triggerR / 255.0f);

  struct {
    uint16_t bit;
    const char* name;
  } buttons[] = {
      {kButtonA, "A"},          {kButtonB, "B"},       {kButtonX, "X"},
      {kButtonY, "Y"},          {kButtonZ, "Z"},       {kButtonStart, "START"},
      {kButtonL, "L"},          {kButtonR, "R"},       {kButtonDpadUp, "D_UP"},
      {kButtonDpadDown, "D_DOWN"}, {kButtonDpadLeft, "D_LEFT"},
      {kButtonDpadRight, "D_RIGHT"},
  };
  for (const auto& button : buttons) {
    const bool pressed = (input.buttons & button.bit) != 0;
    const bool was_pressed = (previousButtons & button.bit) != 0;
    if (pressed && !was_pressed)
      append_command("PRESS %s\n", button.name);
    else if (!pressed && was_pressed)
      append_command("RELEASE %s\n", button.name);
  }
  return commands;
}

std::string GCPadNewIniContents() {
  return
      "[GCPad1]\n"
      "Device = Pipe/0/sunpad\n"
      "Buttons/A = `Button A`\n"
      "Buttons/B = `Button B`\n"
      "Buttons/X = `Button X`\n"
      "Buttons/Y = `Button Y`\n"
      "Buttons/Z = `Button Z`\n"
      "Buttons/Start = `Button START`\n"
      "Main Stick/Up = `Axis MAIN Y -`\n"
      "Main Stick/Down = `Axis MAIN Y +`\n"
      "Main Stick/Left = `Axis MAIN X -`\n"
      "Main Stick/Right = `Axis MAIN X +`\n"
      "Main Stick/Calibration = 100.00\n"
      "C-Stick/Up = `Axis C Y -`\n"
      "C-Stick/Down = `Axis C Y +`\n"
      "C-Stick/Left = `Axis C X -`\n"
      "C-Stick/Right = `Axis C X +`\n"
      "C-Stick/Calibration = 100.00\n"
      "Triggers/L = `Axis L +`\n"
      "Triggers/R = `Axis R +`\n"
      "Triggers/L-Analog = `Axis L +`\n"
      "Triggers/R-Analog = `Axis R +`\n"
      "D-Pad/Up = `Button D_UP`\n"
      "D-Pad/Down = `Button D_DOWN`\n"
      "D-Pad/Left = `Button D_LEFT`\n"
      "D-Pad/Right = `Button D_RIGHT`\n";
}

}  // namespace sunpad
