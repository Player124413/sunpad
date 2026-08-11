#import "SunPadControllerMapping.h"

#include <initializer_list>

static NSString *const SunPadControllerMappingDefaultsKey =
    @"SunPadControllerButtonMappingV1";

static NSArray<NSString *> *SunPadMappingKeys(void) {
    return @[@"A", @"B", @"X", @"Y", @"Z"];
}

static NSArray<NSNumber *> *SunPadMappingValues(SunPadControllerButtonMapping mapping) {
    return @[@(mapping.gameA), @(mapping.gameB), @(mapping.gameX),
             @(mapping.gameY), @(mapping.gameZ)];
}

static SunPadPhysicalControllerButton *SunPadMappingSlot(
    SunPadControllerButtonMapping *mapping, uint16_t gameButton) {
    switch (gameButton) {
    case SunPadButtonA: return &mapping->gameA;
    case SunPadButtonB: return &mapping->gameB;
    case SunPadButtonX: return &mapping->gameX;
    case SunPadButtonY: return &mapping->gameY;
    case SunPadButtonZ: return &mapping->gameZ;
    default: return nullptr;
    }
}

SunPadControllerButtonMapping SunPadDefaultControllerButtonMapping(void) {
    return (SunPadControllerButtonMapping){
        .gameA = SunPadPhysicalControllerButtonA,
        .gameB = SunPadPhysicalControllerButtonB,
        .gameX = SunPadPhysicalControllerButtonX,
        .gameY = SunPadPhysicalControllerButtonY,
        .gameZ = SunPadPhysicalControllerButtonRightShoulder,
    };
}

BOOL SunPadControllerButtonMappingIsValid(SunPadControllerButtonMapping mapping) {
    uint8_t seen = 0;
    const uint8_t allowed = SunPadPhysicalControllerButtonA |
        SunPadPhysicalControllerButtonB | SunPadPhysicalControllerButtonX |
        SunPadPhysicalControllerButtonY |
        SunPadPhysicalControllerButtonRightShoulder;
    for (NSNumber *number in SunPadMappingValues(mapping)) {
        uint8_t value = number.unsignedCharValue;
        if (value == 0 || (value & (value - 1)) != 0 || (value & ~allowed) != 0 ||
            (seen & value) != 0) {
            return NO;
        }
        seen |= value;
    }
    return seen == allowed;
}

uint16_t SunPadApplyControllerButtonMapping(
    SunPadControllerButtonMapping mapping,
    SunPadPhysicalControllerButton pressedButtons) {
    if (!SunPadControllerButtonMappingIsValid(mapping))
        mapping = SunPadDefaultControllerButtonMapping();
    uint16_t gameButtons = 0;
    if (pressedButtons & mapping.gameA) gameButtons |= SunPadButtonA;
    if (pressedButtons & mapping.gameB) gameButtons |= SunPadButtonB;
    if (pressedButtons & mapping.gameX) gameButtons |= SunPadButtonX;
    if (pressedButtons & mapping.gameY) gameButtons |= SunPadButtonY;
    if (pressedButtons & mapping.gameZ) gameButtons |= SunPadButtonZ;
    return gameButtons;
}

SunPadControllerButtonMapping SunPadControllerButtonMappingByAssigning(
    SunPadControllerButtonMapping mapping,
    SunPadPhysicalControllerButton physicalButton,
    uint16_t gameButton) {
    if (!SunPadControllerButtonMappingIsValid(mapping))
        mapping = SunPadDefaultControllerButtonMapping();
    SunPadPhysicalControllerButton *destination = SunPadMappingSlot(&mapping, gameButton);
    if (destination == nullptr)
        return mapping;
    SunPadPhysicalControllerButton previous = *destination;
    if (previous == physicalButton)
        return mapping;
    for (uint16_t candidate : {SunPadButtonA, SunPadButtonB, SunPadButtonX,
                               SunPadButtonY, SunPadButtonZ}) {
        SunPadPhysicalControllerButton *slot = SunPadMappingSlot(&mapping, candidate);
        if (slot != nullptr && *slot == physicalButton) {
            *slot = previous;
            break;
        }
    }
    *destination = physicalButton;
    return mapping;
}

NSString *SunPadPhysicalControllerButtonName(SunPadPhysicalControllerButton button) {
    switch (button) {
    case SunPadPhysicalControllerButtonA: return @"A";
    case SunPadPhysicalControllerButtonB: return @"B";
    case SunPadPhysicalControllerButtonX: return @"X";
    case SunPadPhysicalControllerButtonY: return @"Y";
    case SunPadPhysicalControllerButtonRightShoulder: return @"Right Shoulder";
    default: return @"Unknown";
    }
}

@implementation SunPadControllerMappingStore

+ (SunPadControllerButtonMapping)mapping {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:SunPadControllerMappingDefaultsKey];
    if (saved == nil)
        return SunPadDefaultControllerButtonMapping();
    NSArray<NSString *> *keys = SunPadMappingKeys();
    SunPadControllerButtonMapping mapping = {
        .gameA = (SunPadPhysicalControllerButton)[saved[keys[0]] unsignedCharValue],
        .gameB = (SunPadPhysicalControllerButton)[saved[keys[1]] unsignedCharValue],
        .gameX = (SunPadPhysicalControllerButton)[saved[keys[2]] unsignedCharValue],
        .gameY = (SunPadPhysicalControllerButton)[saved[keys[3]] unsignedCharValue],
        .gameZ = (SunPadPhysicalControllerButton)[saved[keys[4]] unsignedCharValue],
    };
    return SunPadControllerButtonMappingIsValid(mapping)
        ? mapping : SunPadDefaultControllerButtonMapping();
}

+ (void)setMapping:(SunPadControllerButtonMapping)mapping {
    if (!SunPadControllerButtonMappingIsValid(mapping))
        mapping = SunPadDefaultControllerButtonMapping();
    NSArray<NSString *> *keys = SunPadMappingKeys();
    NSArray<NSNumber *> *values = SunPadMappingValues(mapping);
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    for (NSUInteger index = 0; index < keys.count; ++index)
        saved[keys[index]] = values[index];
    [[NSUserDefaults standardUserDefaults] setObject:saved
                                              forKey:SunPadControllerMappingDefaultsKey];
}

+ (void)reset {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SunPadControllerMappingDefaultsKey];
}

@end
