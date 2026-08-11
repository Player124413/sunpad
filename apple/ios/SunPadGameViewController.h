#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/* Root view controller: hosts the Metal game surface and the SunPad overlay
 * (three-dot menu, render resolution, touch controls). */
@interface SunPadGameViewController : UIViewController

/* Forward iOS application lifecycle events to the active game runtime. */
- (void)pauseRuntimeForApplicationLifecycle;
- (void)resumeRuntimeForApplicationLifecycle;

@end

NS_ASSUME_NONNULL_END
