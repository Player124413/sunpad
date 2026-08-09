#import <Foundation/Foundation.h>

#include <algorithm>
#include <cassert>
#include <iostream>
#include <string>

#include "SunPadInputPipeEncoder.h"

static constexpr uint16_t AllButtons =
    SunPadButtonA | SunPadButtonB | SunPadButtonX | SunPadButtonY |
    SunPadButtonZ | SunPadButtonStart | SunPadButtonL | SunPadButtonR |
    SunPadButtonDpadUp | SunPadButtonDpadDown |
    SunPadButtonDpadLeft | SunPadButtonDpadRight;

static size_t CountLines(const std::string &commands) {
    return static_cast<size_t>(std::count(commands.begin(), commands.end(), '\n'));
}

int main(void) {
    @autoreleasepool {
        SunPadInputState neutral = {};
        std::string neutralCommands = SunPadEncodePipeCommands(neutral, 0);
        assert(CountLines(neutralCommands) == 4);
        assert(neutralCommands.find("SET MAIN 0.500 0.500\n") != std::string::npos);

        SunPadInputState pressed = {};
        pressed.buttons = AllButtons;
        pressed.stickX = 127;
        pressed.stickY = -127;
        pressed.cStickX = -127;
        pressed.cStickY = 127;
        pressed.triggerL = 255;
        pressed.triggerR = 255;
        std::string pressCommands = SunPadEncodePipeCommands(pressed, 0);
        assert(CountLines(pressCommands) == 16);
        assert(pressCommands.size() > 128);
        assert(pressCommands.find("PRESS START\n") != std::string::npos);
        assert(pressCommands.find("PRESS D_RIGHT\n") != std::string::npos);

        SunPadInputState released = {};
        std::string releaseCommands = SunPadEncodePipeCommands(released, AllButtons);
        assert(CountLines(releaseCommands) == 16);
        assert(releaseCommands.size() > 128);
        assert(releaseCommands.find("RELEASE START\n") != std::string::npos);
        assert(releaseCommands.find("RELEASE D_RIGHT\n") != std::string::npos);

        std::cout << "SunPad input pipe encoder regression test passed\n";
    }
    return 0;
}
