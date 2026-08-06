#pragma once

#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/* Normalized GameCube controller state, matching BellPad's canonical
 * touch/controller mixer boundary. Sticks are int8 [-127, 127], triggers are
 * uint8 [0, 255] (FLUDD pressure), buttons are a bitmask. */
typedef struct {
    int8_t stickX, stickY;
    int8_t cStickX, cStickY;
    uint8_t triggerL, triggerR;
    uint16_t buttons;
    int connected;
} SunPadInputState;

typedef NS_ENUM(uint16_t, SunPadButton) {
    SunPadButtonDpadLeft = 1 << 0,
    SunPadButtonDpadRight = 1 << 1,
    SunPadButtonDpadDown = 1 << 2,
    SunPadButtonDpadUp = 1 << 3,
    SunPadButtonZ = 1 << 4,
    SunPadButtonR = 1 << 5,
    SunPadButtonL = 1 << 6,
    SunPadButtonA = 1 << 8,
    SunPadButtonB = 1 << 9,
    SunPadButtonX = 1 << 10,
    SunPadButtonY = 1 << 11,
    SunPadButtonStart = 1 << 12,
};

NS_ASSUME_NONNULL_END
