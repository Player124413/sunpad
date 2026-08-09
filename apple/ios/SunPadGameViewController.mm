#import "SunPadGameViewController.h"

#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadDiscExtractor.h"
#import "SunPadGameOverlay.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cmath>

static constexpr CGFloat SunPadDrawableScale = 1.0;

/* UIView whose backing layer is a CAMetalLayer: the ModernGekko Metal video
 * backend renders directly into this layer (Dolphin owns the drawable). */
@interface SunPadMetalSurfaceView : UIView
+ (Class)layerClass;
@end

@implementation SunPadMetalSurfaceView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

@interface SunPadGameViewController () <SunPadGameOverlayDelegate, UIDocumentPickerDelegate>
- (NSString *)modulePathFromConfiguration:(NSDictionary *)configuration;
- (NSString *)resolvedImportTestPath:(NSString *)requestedPath;
@end

@implementation SunPadGameViewController {
    SunPadMetalSurfaceView *_gameView;
    SunPadCoreHost *_coreHost;
    SunPadGameOverlay *_overlay;
    dispatch_source_t _controllerTimer;
    UILabel *_fpsLabel;
    UILabel *_bootStatusLabel;
    CGSize _lastLoggedDrawableSize;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // Super Mario Sunshine is a landscape game; the overlay is designed for
    // landscape like the BellPad reference (never portrait).
    return UIInterfaceOrientationMaskLandscape;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    SunPadLog(@"viewDidLoad bounds=%@ orientation=%ld",
              NSStringFromCGRect(self.view.bounds), (long)UIDevice.currentDevice.orientation);
    self.view.backgroundColor = UIColor.blackColor;

    _gameView = [[SunPadMetalSurfaceView alloc] initWithFrame:self.view.bounds];
    _gameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_gameView];

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * SunPadDrawableScale,
                                    CGRectGetHeight(_gameView.bounds) * SunPadDrawableScale);

    _overlay = [[SunPadGameOverlay alloc] initWithFrame:self.view.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.delegate = self;
    [self.view addSubview:_overlay];

    _bootStatusLabel = [UILabel new];
    _bootStatusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    _bootStatusLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    _bootStatusLabel.textAlignment = NSTextAlignmentCenter;
    _bootStatusLabel.numberOfLines = 0;
    _bootStatusLabel.text = @"Starting SunPad…\nThis can take a little while.";
    [self.view addSubview:_bootStatusLabel];

    _fpsLabel = [UILabel new];
    _fpsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0
                                                      weight:UIFontWeightSemibold];
    _fpsLabel.text = @"";
    _fpsLabel.hidden = YES;
    [self.view addSubview:_fpsLabel];
    [self startFPSMonitor];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    // SunPad is an app-delegate UIKit app rather than a scene-based app. These
    // legacy notifications remain the only direct external-screen signal for
    // this deployment model on iPadOS 16+.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenDidDisconnectNotification
                                               object:nil];
#pragma clang diagnostic pop
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenModeDidChangeNotification
                                               object:nil];
    // DEBUG hook: -sunpadImportTest <iso path> runs the full import flow.
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger importIndex = [arguments indexOfObject:@"-sunpadImportTest"];
    if (importIndex != NSNotFound && importIndex + 1 < arguments.count) {
        NSString *imagePath = [self resolvedImportTestPath:arguments[importIndex + 1]];
        NSLog(@"[SunPad] import test requested=%@ resolved=%@", arguments[importIndex + 1], imagePath);
        [self startInputConsumer];
        [self observeControllers];
        [self importGameDataFromURL:[NSURL fileURLWithPath:imagePath]];
        return;
    }
    [self startGameIfProvisioned];
    [self startInputConsumer];
    [self observeControllers];
}

// Physical-device launches cannot refer to the host's /tmp. devicectl copies
// into the app data container, whose actual temporary directory is returned by
// NSTemporaryDirectory(). Keep the command-line hook usable for both the
// Simulator's host path and the device's injected ISO.
- (NSString *)resolvedImportTestPath:(NSString *)requestedPath {
    if ([[NSFileManager defaultManager] fileExistsAtPath:requestedPath])
        return requestedPath;
    NSString *prefix = @"/tmp/";
    if ([requestedPath hasPrefix:prefix]) {
        NSString *relativePath = [requestedPath substringFromIndex:prefix.length];
        NSString *sandboxPath = [NSTemporaryDirectory() stringByAppendingPathComponent:relativePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:sandboxPath])
            return sandboxPath;
    }
    return requestedPath;
}

- (NSString *)modulePathFromConfiguration:(NSDictionary *)configuration {
    NSString *hostPath = configuration[@"DevModulePath"];
    if (hostPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:hostPath])
        return hostPath;

    NSString *deviceRelativePath = configuration[@"DeviceModuleRelativePath"];
    if (deviceRelativePath.length > 0)
        return [NSTemporaryDirectory() stringByAppendingPathComponent:deviceRelativePath];
    return hostPath;
}

- (void)startFPSMonitor {
    static dispatch_source_t fpsTimer;
    if (fpsTimer)
        return;
    fpsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                      dispatch_get_main_queue());
    dispatch_source_set_timer(fpsTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(fpsTimer, ^{
        [weakSelf updateFPSLabel];
    });
    dispatch_resume(fpsTimer);
}

- (void)updateFPSLabel {
    double fps = [_coreHost currentFPS];
    if (fps > 0.0)
        _bootStatusLabel.hidden = YES;

    if (![SunPadSettings sharedSettings].showFPSCounter) {
        _fpsLabel.hidden = YES;
        return;
    }
    if (fps > 0.0) {
        // Super Mario Sunshine runs at a 30 Hz NTSC frame rate, so FPS ~ 30 is
        // full speed. Dolphin's raw "speed" metric is not wired on the static
        // recomp path and would read misleadingly.
        _fpsLabel.text = [NSString stringWithFormat:@"%.1f FPS", fps];
        _fpsLabel.hidden = NO;
        NSLog(@"[SunPad] FPS: %.1f  EFB: %@", fps, [_coreHost efbResolution]);
    } else {
        _fpsLabel.hidden = YES;
    }
}

- (void)observeControllers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidConnect:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidDisconnect:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    for (GCController *controller in GCController.controllers)
        [self configureController:controller];
}

- (void)controllerDidConnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    SunPadLog(@"controller connected vendor=%@ category=%@ extended=%d count=%lu",
              controller.vendorName ?: @"unknown", controller.productCategory ?: @"unknown",
              controller.extendedGamepad != nil, (unsigned long)GCController.controllers.count);
    [self configureController:notification.object];
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    SunPadLog(@"controller disconnected vendor=%@ count=%lu",
              controller.vendorName ?: @"unknown", (unsigned long)GCController.controllers.count);
    [[SunPadInputMixer sharedMixer] clearInputFromTouch:NO];
}

/* BellPad's GameCube mapping: analog triggers carry L/R pressure (FLUDD),
 * the right shoulder is Z, menu is Start, and the D-pad maps to D-pad bits. */
- (void)configureController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (gamepad == nil) {
        SunPadLog(@"controller ignored vendor=%@ reason=no extended gamepad profile",
                  controller.vendorName ?: @"unknown");
        return;
    }
    SunPadLog(@"controller configured vendor=%@ category=%@",
              controller.vendorName ?: @"unknown", controller.productCategory ?: @"unknown");
    __weak SunPadGameViewController *weakSelf = self;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        (void)weakSelf;
        // Every callback is a complete snapshot. Leaving buttons uninitialized
        // made random button edges overflow the old fixed-size pipe buffer.
        SunPadInputState state = {};
        state.connected = 1;
        if (pad.buttonA.isPressed) state.buttons |= SunPadButtonA;
        if (pad.buttonB.isPressed) state.buttons |= SunPadButtonB;
        if (pad.buttonX.isPressed) state.buttons |= SunPadButtonX;
        if (pad.buttonY.isPressed) state.buttons |= SunPadButtonY;
        if (pad.leftShoulder.isPressed) state.buttons |= SunPadButtonL;
        if (pad.rightShoulder.isPressed) state.buttons |= SunPadButtonZ;
        if (pad.buttonMenu.isPressed) state.buttons |= SunPadButtonStart;
        if (pad.dpad.up.isPressed) state.buttons |= SunPadButtonDpadUp;
        if (pad.dpad.down.isPressed) state.buttons |= SunPadButtonDpadDown;
        if (pad.dpad.left.isPressed) state.buttons |= SunPadButtonDpadLeft;
        if (pad.dpad.right.isPressed) state.buttons |= SunPadButtonDpadRight;
        state.stickX = (int8_t)std::lround(pad.leftThumbstick.xAxis.value * 127.0f);
        state.stickY = (int8_t)std::lround(pad.leftThumbstick.yAxis.value * 127.0f);
        state.cStickX = (int8_t)std::lround(pad.rightThumbstick.xAxis.value * 127.0f);
        state.cStickY = (int8_t)std::lround(pad.rightThumbstick.yAxis.value * 127.0f);
        state.triggerL = (uint8_t)std::lround(pad.leftTrigger.value * 255.0f);
        state.triggerR = (uint8_t)std::lround(pad.rightTrigger.value * 255.0f);
        if (state.triggerL > 30) state.buttons |= SunPadButtonL;
        if (state.triggerR > 30) state.buttons |= SunPadButtonR;
        [[SunPadInputMixer sharedMixer] setInputState:state fromTouch:NO];
    };
    gamepad.valueChangedHandler(gamepad, gamepad.buttonA);
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    [_coreHost setRenderScale:settings.renderScale];
    [_coreHost setAspectRatioMode:settings.aspectRatioMode];
    [self updateFPSLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * SunPadDrawableScale,
                                    CGRectGetHeight(_gameView.bounds) * SunPadDrawableScale);
    if (!CGSizeEqualToSize(_lastLoggedDrawableSize, layer.drawableSize)) {
        _lastLoggedDrawableSize = layer.drawableSize;
        SunPadLog(@"layout bounds=%@ game=%@ drawable=%@",
                  NSStringFromCGRect(self.view.bounds),
                  NSStringFromCGRect(_gameView.bounds),
                  NSStringFromCGSize(layer.drawableSize));
    }
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat statusWidth = MIN(420.0, CGRectGetWidth(safe) - 32.0);
    _bootStatusLabel.frame = CGRectMake(CGRectGetMidX(safe) - statusWidth / 2.0,
                                        CGRectGetMidY(safe) - 40.0,
                                        statusWidth, 80.0);
    _fpsLabel.frame = CGRectMake(CGRectGetMinX(safe) + 8.0,
                                 CGRectGetMinY(safe) + 8.0,
                                 140.0, 22.0);
}

- (void)displayConfigurationChanged:(NSNotification *)notification {
    UIScreen *screen = [notification.object isKindOfClass:UIScreen.class]
        ? notification.object : UIScreen.mainScreen;
    SunPadLog(@"display event=%@ bounds=%@ nativeBounds=%@ scale=%.2f nativeScale=%.2f maxFPS=%ld",
              notification.name,
              NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
              screen.scale, screen.nativeScale, (long)screen.maximumFramesPerSecond);
}

- (void)startGameIfProvisioned {
    if (_coreHost != nil)
        return;
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *configPath = [bundle pathForResource:@"dev-config" ofType:@"plist"];
    if (configPath == nil) {
        SunPadLog(@"boot skipped reason=dev config missing");
        _bootStatusLabel.text = @"SunPad needs its local game data before it can start.";
        return; // Not a dev-provisioned build; import flow is a later stage.
    }
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // App updates can relocate the data-container UUID. On physical devices,
    // derive imported data from the current sandbox instead of trusting an
    // absolute path persisted by a previous installation.
    NSString *supportRoot = [[NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Application Support"]
        stringByAppendingPathComponent:@"SunPad"];
    NSString *gameDataDirectory = [supportRoot stringByAppendingPathComponent:@"GameData"];
    NSString *currentContainerRoot = [gameDataDirectory stringByAppendingPathComponent:@"GMSE01"];
    BOOL currentRootExists = [fileManager fileExistsAtPath:currentContainerRoot];
    NSString *gameRoot = currentContainerRoot;
#if TARGET_OS_SIMULATOR
    if (!currentRootExists)
        gameRoot = config[@"DevGameRoot"];
#endif
    if (![settings.extractedGameRoot isEqualToString:gameRoot]) {
        settings.extractedGameRoot = gameRoot;
        [settings synchronize];
    }
    SunPadLog(@"boot data support=%@ root=%@ rootExists=%d persistedRoot=%@",
              supportRoot, gameRoot, currentRootExists,
              settings.extractedGameRoot ?: @"none");

    NSString *modulePath = [self modulePathFromConfiguration:config];
    if (gameRoot.length == 0 || modulePath.length == 0) {
        SunPadLog(@"boot skipped gameRoot=%d modulePath=%d",
                  gameRoot.length > 0, modulePath.length > 0);
        _bootStatusLabel.text = @"SunPad could not find its local game data.";
        return;
    }

    NSString *userDirectory = supportRoot;
    [[NSFileManager defaultManager] createDirectoryAtPath:userDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Boot from the retained image so Dolphin sees the exact FST, physical
    // file offsets, and streaming layout from the user's disc. In-place app
    // installs preserve the file but change the container UUID, so rebase the
    // persisted absolute path when necessary.
    NSString *discFileName = settings.retainedGameDataPath.lastPathComponent;
    if (discFileName.length == 0) {
        NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:gameDataDirectory
                                                                        error:nil];
        for (NSString *entry in entries) {
            NSString *extension = entry.pathExtension.lowercaseString;
            if ([extension isEqualToString:@"iso"] ||
                [extension isEqualToString:@"gcm"] ||
                [extension isEqualToString:@"rvz"]) {
                discFileName = entry;
                break;
            }
        }
    }
    NSString *rebasedImage = discFileName.length > 0
        ? [gameDataDirectory stringByAppendingPathComponent:discFileName] : @"";
    NSString *discImagePath = rebasedImage;
#if TARGET_OS_SIMULATOR
    if (rebasedImage.length == 0 || ![fileManager fileExistsAtPath:rebasedImage])
        discImagePath = settings.retainedGameDataPath ?: @"";
#endif
    if (discImagePath.length > 0 &&
        ![settings.retainedGameDataPath isEqualToString:discImagePath]) {
        settings.retainedGameDataPath = discImagePath;
        [settings synchronize];
    }
    SunPadLog(@"boot disc path=%@ exists=%d", discImagePath.length > 0
              ? discImagePath.lastPathComponent : @"none",
              discImagePath.length > 0 && [fileManager fileExistsAtPath:discImagePath]);

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    SunPadLog(@"boot requested gameRootExists=%d discImage=%d moduleExists=%d drawable=%@",
              [fileManager fileExistsAtPath:gameRoot], discImagePath.length > 0,
              [fileManager fileExistsAtPath:modulePath], NSStringFromCGSize(layer.drawableSize));
    _coreHost = [[SunPadCoreHost alloc] initWithLayer:layer];
    __weak SunPadGameViewController *weakSelf = self;
    [_coreHost startWithGameRoot:gameRoot
                   discImagePath:discImagePath ?: @""
                      modulePath:modulePath
                   userDirectory:userDirectory
                         onError:^(NSString *message) {
        [weakSelf presentBootError:message];
    }];
}

- (void)presentBootError:(NSString *)message {
    _bootStatusLabel.text = @"SunPad could not start.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SunPad could not start"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startInputConsumer {
    // Feed the game thread the merged touch+controller snapshot at 60 Hz.
    if (_controllerTimer)
        return;
    _controllerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
    dispatch_source_set_timer(_controllerTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 / 60.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(_controllerTimer, ^{
        [weakSelf publishMergedInput];
    });
    dispatch_resume(_controllerTimer);
}

- (void)publishMergedInput {
    SunPadInputState merged = [[SunPadInputMixer sharedMixer] consumeMergedState];
    [_coreHost publishInput:merged];
}

#pragma mark - SunPadGameOverlayDelegate

- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay {
    (void)overlay;
    // Document-picker game-data import flow is wired in the app delegate; the
    // overlay requests a change/reimport here.
    [self presentGameDataImport];
}

- (void)presentGameDataImport {
    NSArray<UTType *> *types = @[
        [UTType typeWithFilenameExtension:@"iso"],
        [UTType typeWithFilenameExtension:@"gcm"],
        [UTType typeWithFilenameExtension:@"rvz"],
        UTTypeData,
    ];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                               asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (url == nil)
        return;
    [self importGameDataFromURL:url];
}

- (void)importGameDataFromURL:(NSURL *)url {
    NSLog(@"[SunPad] import start: %@", url.path);
    NSString *message = [self validateGameDataAtURL:url];
    if (message != nil) {
        NSLog(@"[SunPad] import validation failed: %@", message);
        [self presentBootError:message];
        return;
    }

    // Stage the image into private Application Support (never the bundle).
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dataDir = [paths.firstObject stringByAppendingPathComponent:@"SunPad/GameData"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dataDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *destination =
        [dataDir stringByAppendingPathComponent:url.lastPathComponent];
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:url.path
                                                 toPath:destination
                                                  error:&copyError]) {
        NSLog(@"[SunPad] import copy failed: %@", copyError);
        [self presentBootError:[NSString stringWithFormat:@"Could not retain the game image: %@",
                                                          copyError.localizedDescription]];
        return;
    }
    NSLog(@"[SunPad] import retained at %@", destination);
    [SunPadSettings sharedSettings].retainedGameDataPath = destination;
    [[SunPadSettings sharedSettings] synchronize];

    NSArray<NSString *> *extractPaths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *extractRoot = [[extractPaths.firstObject
        stringByAppendingPathComponent:@"SunPad/GameData"]
        stringByAppendingPathComponent:@"GMSE01"];

    UIAlertController *progressAlert =
        [UIAlertController alertControllerWithTitle:@"Importing Game Data"
                                            message:@"Extracting the disc…"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    __weak SunPadGameViewController *weakSelf = self;
    [SunPadDiscExtractor extractImageAtPath:destination
                               toDirectory:extractRoot
                                   progress:^(NSString *status, double fraction) {
        progressAlert.message = [NSString stringWithFormat:@"%@ (%.0f%%)", status, fraction * 100.0];
    }
                                 completion:^(BOOL ok, NSString *error) {
        SunPadGameViewController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        [progressAlert dismissViewControllerAnimated:YES completion:nil];
        if (!ok) {
            [strongSelf presentBootError:error ?: @"Extraction failed."];
            return;
        }
        [SunPadSettings sharedSettings].extractedGameRoot = extractRoot;
        [[SunPadSettings sharedSettings] synchronize];

        NSBundle *bundle = NSBundle.mainBundle;
        NSString *configPath = [bundle pathForResource:@"dev-config" ofType:@"plist"];
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
        NSString *modulePath = [strongSelf modulePathFromConfiguration:config];
        if (strongSelf->_coreHost != nil) {
            [strongSelf->_coreHost restartWithGameRoot:extractRoot
                                         discImagePath:destination
                                            modulePath:modulePath];
        } else {
            [strongSelf startGameIfProvisioned];
        }
    }];
}

- (nullable NSString *)validateGameDataAtURL:(NSURL *)url {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (handle == nil)
        return @"The selected file could not be opened.";
    NSData *header = [handle readDataOfLength:0x100];
    [handle closeFile];
    if (header.length < 0x100)
        return @"The file is too small to be a GameCube image.";

    const uint8_t *bytes = (const uint8_t *)header.bytes;
    uint32_t magic = CFSwapInt32BigToHost(*(uint32_t *)(bytes + 0x1C));
    if (magic != 0xC2339F3D)
        return @"The file is not a GameCube disc image (bad magic).";
    char gameId[7] = {0};
    // The GameCube disc header starts with the six-character game code.
    memcpy(gameId, bytes + 0x00, 6);
    if (strncmp(gameId, "GMSE01", 6) != 0)
        return [NSString stringWithFormat:@"Unsupported game ID '%s'; SunPad currently supports GMSE01 (Super Mario Sunshine USA).", gameId];
    return nil;
}

@end
