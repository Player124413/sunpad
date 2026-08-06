#pragma once

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

/* Hosts the ModernGekko / Dolphin-derived compatibility runtime inside the
 * SunPad iOS/iPadOS app. Owns the game thread, the CAMetalLayer render
 * surface handed to the Metal video backend, and the pipe-input bridge. */
@interface SunPadCoreHost : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Boots the game on a background thread. Returns immediately; the game runs
 * until -stop is called. Reports errors through onError. */
- (void)startWithGameRoot:(NSString *)gameRoot
              modulePath:(NSString *)modulePath
              userDirectory:(NSString *)userDirectory
                  onError:(void (^)(NSString *message))onError;

- (void)stop;

/* Stops the current runtime (if any) and boots the game at gameRoot with the
 * given module. Used after an imported image is extracted. */
- (void)restartWithGameRoot:(NSString *)gameRoot
                 modulePath:(NSString *)modulePath;

/* Publishes the normalized input snapshot to the game through the pipe
 * device. Safe to call from any thread at ~60 Hz. */
- (void)publishInput:(SunPadInputState)input;

/* Applies the render-resolution scale (0 = native/default, 1..4 = EFB scale)
 * to the running runtime. Safe to call from any thread. */
- (void)setRenderScale:(NSInteger)scale;

/* Current emulated FPS from the runtime (0 if not booted). */
- (double)currentFPS;

/* Emulation speed relative to real time (100 = full speed). */
- (double)currentSpeed;

/* Internal (EFB) render resolution, e.g. "640x528". */
- (NSString *)efbResolution;

@property(nonatomic, readonly, getter=isRunning) BOOL running;

@end

NS_ASSUME_NONNULL_END
