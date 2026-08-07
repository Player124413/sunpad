#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Persisted SunPad settings shared by macOS, iOS, and iPadOS. Stored in
 * NSUserDefaults so each platform keeps the same user-facing options.
 */
@interface SunPadSettings : NSObject

+ (instancetype)sharedSettings;

/* Render-resolution scale. 1 = native GameCube EFB, 2..4 = multiplier. */
@property(nonatomic, assign) NSInteger renderScale;
- (float)renderScaleFloat;

/* Optional developer performance overlay. Off by default for normal play. */
@property(nonatomic, assign) BOOL showFPSCounter;

/* Touch-control presentation. */
@property(nonatomic, assign) BOOL hideTouchControlsWhenControllerConnected;
@property(nonatomic, assign) CGFloat controlOpacity;   // 0.25..1
@property(nonatomic, assign) CGFloat controlSizeScale; // 0.70..1.35
@property(nonatomic, assign) BOOL editingControlLayout;

/* Per-control size overrides (1.0 = default), keyed by control identifier. */
- (CGFloat)sizeScaleForControl:(NSString *)identifier;
- (void)setSizeScale:(CGFloat)scale forControl:(NSString *)identifier;
- (void)resetControlSizeScales;

/* Save/load the retained game-data path (Application Support on mobile). */
@property(nonatomic, copy, nullable) NSString *retainedGameDataPath;

/* Extracted game tree (sys/ + files/) produced from the retained image. */
@property(nonatomic, copy, nullable) NSString *extractedGameRoot;

- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
