#pragma once

#import <Foundation/Foundation.h>

#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

/* Merges touch and GameController input into one normalized GameCube state,
 * matching BellPad's canonical mixer: buttons are OR'ed with rising-edge
 * latching, sticks are strongest-wins, triggers are max. The game thread
 * consumes the merged snapshot once per frame. */
@interface SunPadInputMixer : NSObject

+ (instancetype)sharedMixer;

- (void)setInputState:(SunPadInputState)state fromTouch:(BOOL)touch;
- (void)clearInputFromTouch:(BOOL)touch;

/* Returns the merged snapshot and clears consumed latched edges. */
- (SunPadInputState)consumeMergedState;

@end

NS_ASSUME_NONNULL_END
