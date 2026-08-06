#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Persisted SunPad settings shared by macOS, iOS, and iPadOS. Stored in
 * NSUserDefaults so each platform keeps the same user-facing options.
 */
@interface SunPadSettings : NSObject

+ (instancetype)sharedSettings;

/* Render-resolution scale. 0 = native drawable resolution, 1..4 = EFB scale
 * multiplier. Mirrors BellPad's Native/1x/2x/3x/4x render choices. */
@property(nonatomic, assign) NSInteger renderScale;
- (float)renderScaleFloat;

/* Touch-control presentation. */
@property(nonatomic, assign) BOOL hideTouchControlsWhenControllerConnected;
@property(nonatomic, assign) CGFloat controlOpacity;   // 0.25..1
@property(nonatomic, assign) CGFloat controlSizeScale; // 0.70..1.35
@property(nonatomic, assign) BOOL editingControlLayout;

/* Per-control size overrides (1.0 = default), keyed by control identifier. */
- (CGFloat)sizeScaleForControl:(NSString *)identifier;
- (void)setSizeScale:(CGFloat)scale forControl:(NSString *)identifier;

/* Save/load the retained game-data path (Application Support on mobile). */
@property(nonatomic, copy, nullable) NSString *retainedGameDataPath;

- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
