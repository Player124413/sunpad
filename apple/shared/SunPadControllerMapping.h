#pragma once

#import <Foundation/Foundation.h>

#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(uint8_t, SunPadPhysicalControllerButton) {
    SunPadPhysicalControllerButtonA = 1 << 0,
    SunPadPhysicalControllerButtonB = 1 << 1,
    SunPadPhysicalControllerButtonX = 1 << 2,
    SunPadPhysicalControllerButtonY = 1 << 3,
    SunPadPhysicalControllerButtonRightShoulder = 1 << 4,
};

typedef struct {
    SunPadPhysicalControllerButton gameA;
    SunPadPhysicalControllerButton gameB;
    SunPadPhysicalControllerButton gameX;
    SunPadPhysicalControllerButton gameY;
    SunPadPhysicalControllerButton gameZ;
} SunPadControllerButtonMapping;

FOUNDATION_EXPORT SunPadControllerButtonMapping SunPadDefaultControllerButtonMapping(void);
FOUNDATION_EXPORT BOOL SunPadControllerButtonMappingIsValid(
    SunPadControllerButtonMapping mapping);
FOUNDATION_EXPORT uint16_t SunPadApplyControllerButtonMapping(
    SunPadControllerButtonMapping mapping,
    SunPadPhysicalControllerButton pressedButtons);
FOUNDATION_EXPORT SunPadControllerButtonMapping SunPadControllerButtonMappingByAssigning(
    SunPadControllerButtonMapping mapping,
    SunPadPhysicalControllerButton physicalButton,
    uint16_t gameButton);
FOUNDATION_EXPORT NSString *SunPadPhysicalControllerButtonName(
    SunPadPhysicalControllerButton button);

/* Versioned, app-local persistence for the deliberately narrow A/B/X/Y/Z
 * remapping layer. Sticks, D-pad, Menu, left shoulder, and analog triggers
 * remain outside this store and keep their established direct mappings. */
@interface SunPadControllerMappingStore : NSObject

+ (SunPadControllerButtonMapping)mapping;
+ (void)setMapping:(SunPadControllerButtonMapping)mapping;
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
