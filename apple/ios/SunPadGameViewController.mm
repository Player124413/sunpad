#import "SunPadGameViewController.h"

#import "SunPadCoreHost.h"
#import "SunPadDiscExtractor.h"
#import "SunPadGameOverlay.h"
#import "SunPadSettings.h"

#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
@end

@implementation SunPadGameViewController {
    SunPadMetalSurfaceView *_gameView;
    SunPadCoreHost *_coreHost;
    SunPadGameOverlay *_overlay;
    SunPadInputState _controllerInput;
    dispatch_source_t _controllerTimer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _gameView = [[SunPadMetalSurfaceView alloc] initWithFrame:self.view.bounds];
    _gameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_gameView];

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * 2.0,
                                    CGRectGetHeight(_gameView.bounds) * 2.0);

    _overlay = [[SunPadGameOverlay alloc] initWithFrame:self.view.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.delegate = self;
    [self.view addSubview:_overlay];

    [self observeControllerConnection];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    // DEBUG hook: -sunpadImportTest <iso path> runs the full import flow.
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger importIndex = [arguments indexOfObject:@"-sunpadImportTest"];
    if (importIndex != NSNotFound && importIndex + 1 < arguments.count) {
        [self importGameDataFromURL:[NSURL fileURLWithPath:arguments[importIndex + 1]]];
        return;
    }
    [self startGameIfProvisioned];
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    [_coreHost setRenderScale:[SunPadSettings sharedSettings].renderScale];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * 2.0,
                                    CGRectGetHeight(_gameView.bounds) * 2.0);
}

- (void)startGameIfProvisioned {
    if (_coreHost != nil)
        return;
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *configPath = [bundle pathForResource:@"dev-config" ofType:@"plist"];
    if (configPath == nil)
        return; // Not a dev-provisioned build; import flow is a later stage.
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    // Prefer an extracted root produced from an imported image; fall back to
    // the dev-provisioned tree for acceptance testing on the Simulator.
    NSString *gameRoot = [SunPadSettings sharedSettings].extractedGameRoot;
    if (gameRoot.length == 0)
        gameRoot = config[@"DevGameRoot"];
    NSString *modulePath = config[@"DevModulePath"];
    if (gameRoot.length == 0 || modulePath.length == 0)
        return;

    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *userDirectory = [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    _coreHost = [[SunPadCoreHost alloc] initWithLayer:layer];
    __weak SunPadGameViewController *weakSelf = self;
    [_coreHost startWithGameRoot:gameRoot
                      modulePath:modulePath
                   userDirectory:userDirectory
                         onError:^(NSString *message) {
        [weakSelf presentBootError:message];
    }];
}

- (void)presentBootError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SunPad could not start"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)observeControllerConnection {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerConnected)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerConnected)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
}

- (void)controllerConnected {
    // Poll controllers on a light timer and merge into the overlay input.
    if (_controllerTimer)
        dispatch_source_cancel(_controllerTimer);
    if (GCController.controllers.count == 0)
        return;
    _controllerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
    dispatch_source_set_timer(_controllerTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 / 60.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(_controllerTimer, ^{
        [weakSelf pollControllers];
    });
    dispatch_resume(_controllerTimer);
}

- (void)pollControllers {
    _controllerInput = (SunPadInputState){0};
    for (GCController *controller in GCController.controllers) {
        GCControllerDirectionPad *stick = controller.extendedGamepad.leftThumbstick;
        GCControllerDirectionPad *c = controller.extendedGamepad.rightThumbstick;
        GCControllerButtonInput *a = controller.extendedGamepad.buttonA;
        GCControllerButtonInput *b = controller.extendedGamepad.buttonB;
        GCControllerButtonInput *x = controller.extendedGamepad.buttonX;
        GCControllerButtonInput *y = controller.extendedGamepad.buttonY;
        GCControllerButtonInput *l = controller.extendedGamepad.leftShoulder;
        GCControllerButtonInput *r = controller.extendedGamepad.rightShoulder;
        _controllerInput.mainX = stick.xAxis.value;
        _controllerInput.mainY = -stick.yAxis.value;
        _controllerInput.cX = c.xAxis.value;
        _controllerInput.cY = -c.yAxis.value;
        _controllerInput.triggerL = l.value;
        _controllerInput.triggerR = r.value;
        if (a.isPressed) _controllerInput.buttons |= SunPadButtonA;
        if (b.isPressed) _controllerInput.buttons |= SunPadButtonB;
        if (x.isPressed) _controllerInput.buttons |= SunPadButtonX;
        if (y.isPressed) _controllerInput.buttons |= SunPadButtonY;
        if (l.isPressed) _controllerInput.buttons |= SunPadButtonL;
        if (r.isPressed) _controllerInput.buttons |= SunPadButtonR;
        _controllerInput.connected = 1;
        break;
    }
    [_overlay setTouchControlsHidden:
        _controllerInput.connected &&
        [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected
                               animated:YES];
}

#pragma mark - SunPadGameOverlayDelegate

- (void)gameOverlay:(SunPadGameOverlay *)overlay didUpdateInput:(SunPadInputState)input {
    (void)overlay;
    SunPadInputState merged = input;
    if (_controllerInput.connected) {
        // Physical controller takes precedence over touch.
        merged = _controllerInput;
    }
    [_coreHost publishInput:merged];
}

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
        [progressAlert dismissViewControllerAnimated:YES completion:nil];
        if (!ok) {
            [weakSelf presentBootError:error ?: @"Extraction failed."];
            return;
        }
        [SunPadSettings sharedSettings].extractedGameRoot = extractRoot;
        [[SunPadSettings sharedSettings] synchronize];

        NSBundle *bundle = NSBundle.mainBundle;
        NSString *configPath = [bundle pathForResource:@"dev-config" ofType:@"plist"];
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
        NSString *modulePath = config[@"DevModulePath"];
        [_coreHost restartWithGameRoot:extractRoot modulePath:modulePath];
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
