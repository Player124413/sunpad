#import <UIKit/UIKit.h>
#import <os/proc.h>

#import "SunPadDiagnostics.h"
#import "SunPadGameViewController.h"

@interface SunPadAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

static void SunPadRestorePreferencesIfRequested(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (![arguments containsObject:@"-sunpadRestorePreferences"])
        return;

    NSString *restorePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"tmp"]
        stringByAppendingPathComponent:@"SunPadPreferencesRestore.plist"];
    NSDictionary *restored = [NSDictionary dictionaryWithContentsOfFile:restorePath];
    if (restored.count == 0) {
        SunPadLog(@"preferences restore skipped path=%@ reason=missing or empty", restorePath);
        return;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in restored)
        [defaults setObject:restored[key] forKey:key];
    [defaults synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:restorePath error:nil];
    SunPadLog(@"preferences restored keys=%lu", (unsigned long)restored.count);
}

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

    SunPadDiagnosticsStart();
    SunPadRestorePreferencesIfRequested();
    UIScreen *screen = UIScreen.mainScreen;
    SunPadLog(@"launch screen bounds=%@ nativeBounds=%@ scale=%.2f nativeScale=%.2f maxFPS=%ld",
              NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
              screen.scale, screen.nativeScale, (long)screen.maximumFramesPerSecond);

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    SunPadGameViewController *root = [[SunPadGameViewController alloc] init];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle didBecomeActive");
    // Resume the game runtime host.
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle willResignActive");
    // Pause the game runtime host.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle didEnterBackground");
    // Flush saves before suspension (Stage 4 lifecycle gate).
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle willEnterForeground");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    (void)application;
    SunPadLog(@"memory warning physical=%llu available=%llu",
              (unsigned long long)NSProcessInfo.processInfo.physicalMemory,
              (unsigned long long)os_proc_available_memory());
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle willTerminate");
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SunPadAppDelegate class]));
    }
}
