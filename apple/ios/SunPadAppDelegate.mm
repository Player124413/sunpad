#import <UIKit/UIKit.h>

#import "SunPadGameViewController.h"

@interface SunPadAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SunPadAppDelegate

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    // Super Mario Sunshine is a landscape-only experience.
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    SunPadGameViewController *root = [[SunPadGameViewController alloc] init];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    // Resume the game runtime host.
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    // Pause the game runtime host.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    // Flush saves before suspension (Stage 4 lifecycle gate).
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SunPadAppDelegate class]));
    }
}
