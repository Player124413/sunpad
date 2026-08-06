#import "SunPadGameViewController.h"

#import "SunPadGameOverlay.h"
#import "SunPadSettings.h"

#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface SunPadMetalRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (void)setScale:(float)scale;
@end

@implementation SunPadMetalRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    float _scale;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        _queue = [device newCommandQueue];
        _scale = 0.0f;
    }
    return self;
}

- (void)setScale:(float)scale {
    _scale = scale;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (pass == nil || drawable == nil)
        return;
    // SunPad brand clear color; the game's EFB content replaces this once the
    // shared runtime is attached to the surface.
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.055, 0.42, 0.62, 1.0);
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

@end

@interface SunPadGameViewController () <SunPadGameOverlayDelegate>
@end

@implementation SunPadGameViewController {
    MTKView *_gameView;
    SunPadMetalRenderer *_renderer;
    SunPadGameOverlay *_overlay;
    SunPadInputState _controllerInput;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _gameView = [[MTKView alloc] initWithFrame:self.view.bounds device:device];
    _gameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gameView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _renderer = [[SunPadMetalRenderer alloc] initWithDevice:device];
    _gameView.delegate = _renderer;
    [self.view addSubview:_gameView];

    _overlay = [[SunPadGameOverlay alloc] initWithFrame:self.view.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.delegate = self;
    [self.view addSubview:_overlay];

    [self applyRenderScale];
    [self observeControllerConnection];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyRenderScale];
}

- (void)applyRenderScale {
    float scale = [SunPadSettings sharedSettings].renderScaleFloat;
    [_renderer setScale:scale];
    CGSize pointSize = self.view.bounds.size;
    CGFloat screenScale = UIScreen.mainScreen.scale;
    CGFloat pixelScale = MAX(1.0f, screenScale);
    CGFloat multiplier = scale > 0.0f ? scale : pixelScale;
    _gameView.drawableSize = CGSizeMake(pointSize.width * multiplier,
                                        pointSize.height * multiplier);
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
    static dispatch_source_t timer;
    if (timer)
        dispatch_source_cancel(timer);
    if (GCController.controllers.count == 0)
        return;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                   dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 / 60.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf pollControllers];
    });
    dispatch_resume(timer);
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
    (void)input;
    // Merged input is published to the game runtime host. The runtime bridge
    // consumes this snapshot on the game thread (BellPad's pattern).
}

- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay {
    (void)overlay;
    // Document-picker game-data import flow is wired in the app delegate; the
    // overlay requests a change/reimport here.
    [self presentGameDataImport];
}

- (void)presentGameDataImport {
    // TODO(Stage 4): present a UIDocumentPickerViewController that validates
    // the GMSE01 image (header, size, SHA-256) and installs it into private
    // Application Support, following BellPad's validated import flow.
}

@end
