#import <UIKit/UIKit.h>
#import <os/proc.h>

#import "SunPadDiagnostics.h"
#import "SunPadGameViewController.h"

@interface SunPadAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic) UIBackgroundTaskIdentifier saveFlushTask;
- (void)beginSaveFlushGraceForApplication:(UIApplication *)application;
- (void)endSaveFlushGraceForApplication:(UIApplication *)application reason:(NSString *)reason;
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
    self.saveFlushTask = UIBackgroundTaskInvalid;
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
    SunPadLog(@"lifecycle didBecomeActive");
    [self endSaveFlushGraceForApplication:application reason:@"active"];
    [(SunPadGameViewController *)self.window.rootViewController
        resumeRuntimeForApplicationLifecycle];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    SunPadLog(@"lifecycle willResignActive");
    [(SunPadGameViewController *)self.window.rootViewController
        pauseRuntimeForApplicationLifecycle];
    [self beginSaveFlushGraceForApplication:application];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle didEnterBackground");
}

- (void)beginSaveFlushGraceForApplication:(UIApplication *)application {
    // Dolphin's GCI-folder backend flushes one second after writes stop. The
    // runtime was paused in applicationWillResignActive, so keep the process
    // alive briefly enough for that existing save thread to finish without
    // forcing a shutdown or reaching into its private memory-card state.
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    __weak SunPadAppDelegate *weakSelf = self;
    task = [application beginBackgroundTaskWithName:@"SunPad save flush grace"
                                  expirationHandler:^{
        SunPadAppDelegate *strongSelf = weakSelf;
        if (strongSelf.saveFlushTask == task)
            [strongSelf endSaveFlushGraceForApplication:application reason:@"expired"];
    }];
    if (task == UIBackgroundTaskInvalid) {
        SunPadLog(@"lifecycle save flush grace unavailable");
        return;
    }

    if (self.saveFlushTask != UIBackgroundTaskInvalid)
        [self endSaveFlushGraceForApplication:application reason:@"replaced"];
    self.saveFlushTask = task;
    SunPadLog(@"lifecycle save flush grace started");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        SunPadAppDelegate *strongSelf = weakSelf;
        if (strongSelf.saveFlushTask == task)
            [strongSelf endSaveFlushGraceForApplication:application reason:@"timer"];
    });
}

- (void)endSaveFlushGraceForApplication:(UIApplication *)application reason:(NSString *)reason {
    UIBackgroundTaskIdentifier task = self.saveFlushTask;
    if (task == UIBackgroundTaskInvalid)
        return;
    self.saveFlushTask = UIBackgroundTaskInvalid;
    [application endBackgroundTask:task];
    SunPadLog(@"lifecycle save flush grace ended reason=%@", reason);
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
