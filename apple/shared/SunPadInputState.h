#pragma once

#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/* Normalized GameCube controller state consumed by the game runtime. Sticks
 * and triggers are [-1, 1]; buttons are 0 or 1. Mirrors BellPad's canonical
 * touch/controller mixer boundary. */
typedef struct {
    float mainX, mainY;
    float cX, cY;
    float triggerL, triggerR;
    uint16_t buttons; // bitmask; see SunPadButton enum below
    int connected;
} SunPadInputState;

typedef NS_ENUM(uint16_t, SunPadButton) {
    SunPadButtonA = 1 << 0,
    SunPadButtonB = 1 << 1,
    SunPadButtonX = 1 << 2,
    SunPadButtonY = 1 << 3,
    SunPadButtonStart = 1 << 4,
    SunPadButtonZ = 1 << 5,
    SunPadButtonL = 1 << 6,
    SunPadButtonR = 1 << 7,
    SunPadButtonUp = 1 << 8,
    SunPadButtonDown = 1 << 9,
    SunPadButtonLeft = 1 << 10,
    SunPadButtonRight = 1 << 11,
};

NS_ASSUME_NONNULL_END
