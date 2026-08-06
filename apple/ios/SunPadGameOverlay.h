#pragma once

#import <UIKit/UIKit.h>

#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

@class SunPadGameOverlay;

@protocol SunPadGameOverlayDelegate <NSObject>
/* The touch controls or GameController published a new input snapshot. */
- (void)gameOverlay:(SunPadGameOverlay *)overlay didUpdateInput:(SunPadInputState)input;
/* The user asked to change or reimport the game data image. */
- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay;
@end

/* UIKit overlay above the game render surface: the three-dot menu, render
 * resolution choices (Native/1x/2x/3x/4x), touch-control settings, and the
 * Sunshine GameCube touch controls. Patterns adapted from BellPad. */
@interface SunPadGameOverlay : UIView

@property(nonatomic, weak, nullable) id<SunPadGameOverlayDelegate> delegate;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/* Hide the touch controls (e.g., a physical controller is connected). */
- (void)setTouchControlsHidden:(BOOL)hidden animated:(BOOL)animated;

/* Applies persisted settings to the touch controls. */
- (void)applySettings;

/* The current normalized input snapshot (touch + controller merged). */
- (SunPadInputState)currentInputState;

@end

NS_ASSUME_NONNULL_END
