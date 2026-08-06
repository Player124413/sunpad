#import "SunPadGameOverlay.h"

#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#import <GameController/GameController.h>

#include <algorithm>
#include <cmath>

@interface SunPadStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@property(nonatomic, readonly) BOOL active;
- (void)reset;
@end

@implementation SunPadStickView {
    UIView *_thumb;
    float _valueX, _valueY;
    BOOL _active;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.34].CGColor;
        self.layer.borderWidth = 2.0;
        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.32];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = std::min(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = side * 0.5;
    CGFloat thumbDiameter = side * 0.42;
    _thumb.bounds = CGRectMake(0, 0, thumbDiameter, thumbDiameter);
    _thumb.layer.cornerRadius = thumbDiameter * 0.5;
    [self updateThumbCenter];
}

- (void)updateThumbCenter {
    CGFloat half = self.bounds.size.width * 0.5;
    CGFloat maxTravel = half - _thumb.bounds.size.width * 0.5 - 3.0;
    _thumb.center = CGPointMake(half + _valueX * maxTravel,
                                half + _valueY * maxTravel);
}

- (void)setValueX:(float)x y:(float)y {
    _valueX = x;
    _valueY = y;
    [self updateThumbCenter];
}

- (BOOL)active {
    return _active;
}

- (void)reset {
    _active = NO;
    _valueX = _valueY = 0.0f;
    [self updateThumbCenter];
    if (self.valueChanged)
        self.valueChanged(0.0f, 0.0f);
}

- (void)handleTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = std::max<CGFloat>(1.0, std::min(self.bounds.size.width,
                                                     self.bounds.size.height) * 0.5);
    CGFloat dx = (p.x - center.x) / radius;
    CGFloat dy = (p.y - center.y) / radius;
    CGFloat length = hypot(dx, dy);
    if (length > 1.0) {
        dx /= length;
        dy /= length;
    }
    CGFloat thumbRadius = _thumb.bounds.size.width * 0.5;
    CGFloat travel = std::max<CGFloat>(0.0, radius - thumbRadius - 4.0);
    _thumb.center = CGPointMake(center.x + dx * travel, center.y + dy * travel);
    // BellPad: positive Y is up (negate UIKit's down-positive coordinate).
    _valueX = (float)dx;
    _valueY = (float)(-dy);
    _active = YES;
    if (self.valueChanged)
        self.valueChanged(_valueX, _valueY);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self reset];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self reset];
}

@end

@interface SunPadGameButton : UIButton
@property(nonatomic, assign) uint16_t inputMask;
@end

@implementation SunPadGameButton
@end

@interface SunPadGameOverlay () <UIGestureRecognizerDelegate>
@end

@implementation SunPadGameOverlay {
    UIButton *_menuButton;          // the three-dot menu
    SunPadStickView *_moveStick;
    SunPadStickView *_cStick;
    NSMutableArray<SunPadGameButton *> *_buttons;
    NSMutableDictionary<NSString *, UIPanGestureRecognizer *> *_controlDrags;
    NSMutableDictionary<NSString *, NSValue *> *_controlOrigins;

    UIView *_settingsPanel;
    UISegmentedControl *_renderScaleControl;
    UISlider *_opacitySlider;
    UISlider *_sizeSlider;
    UISwitch *_hideControlsSwitch;
    UISwitch *_editLayoutSwitch;

    SunPadInputState _touchState;
    BOOL _touchControlsHidden;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        [self buildMenuButton];
        [self buildTouchControls];
        [self buildSettingsPanel];
        [self applySettings];
        [self observeControllerConnection];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Three-dot menu

- (void)buildMenuButton {
    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_menuButton setTitle:@"⋯" forState:UIControlStateNormal];
    [_menuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _menuButton.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    _menuButton.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    _menuButton.layer.cornerRadius = 20.0;
    _menuButton.layer.borderWidth = 1.0;
    _menuButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _menuButton.accessibilityLabel = @"Menu";
    _menuButton.showsMenuAsPrimaryAction = YES;
    _menuButton.menu = [self buildMenu];
    [self addSubview:_menuButton];
}

- (UIMenu *)buildMenu {
    __weak SunPadGameOverlay *weakSelf = self;

    UIMenu *renderMenu = [UIMenu menuWithTitle:@"Render Resolution" children:@[
        [self renderAction:@"Native" scale:0],
        [self renderAction:@"1×" scale:1],
        [self renderAction:@"2×" scale:2],
        [self renderAction:@"3×" scale:3],
        [self renderAction:@"4×" scale:4],
    ]];

    UIMenu *dataMenu = [UIMenu menuWithTitle:@"Game Data & Saves" children:@[
        [UIAction actionWithTitle:@"Change or Reimport Game Data"
                            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsGameDataChange:weakSelf];
        }],
        [UIAction actionWithTitle:@"Remove Stored Game Data"
                            image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf confirmGameDataRemoval];
        }],
    ]];

    return [UIMenu menuWithTitle:@"SunPad" children:@[
        renderMenu,
        [UIAction actionWithTitle:@"Touch Control Settings…"
                            image:[UIImage systemImageNamed:@"hand.draw"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf toggleSettingsPanel];
        }],
        dataMenu,
    ]];
}

- (UIAction *)renderAction:(NSString *)title scale:(NSInteger)scale {
    __weak SunPadGameOverlay *weakSelf = self;
    return [UIAction actionWithTitle:title
                               image:nil
                          identifier:nil
                             handler:^(__kindof UIAction *action) {
        (void)action;
        [SunPadSettings sharedSettings].renderScale = scale;
        [[SunPadSettings sharedSettings] synchronize];
        [weakSelf refreshMenuButton];
    }];
}

- (void)refreshMenuButton {
    _menuButton.menu = [self buildMenu];
}

- (void)confirmGameDataRemoval {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Remove Stored Game Data?"
                                            message:@"The retained game image will be removed on the next launch. Your save files are not affected."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [[SunPadSettings sharedSettings] setRetainedGameDataPath:nil];
        [[SunPadSettings sharedSettings] setExtractedGameRoot:nil];
        [[SunPadSettings sharedSettings] synchronize];
        [weakSelf.delegate gameOverlayRequestsGameDataChange:weakSelf];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Touch controls

- (void)buildTouchControls {
    _buttons = [NSMutableArray array];
    _controlDrags = [NSMutableDictionary dictionary];
    _controlOrigins = [NSMutableDictionary dictionary];

    _moveStick = [self makeStick];
    _cStick = [self makeStick];
    [self addSubview:_moveStick];
    [self addSubview:_cStick];

    [self addButton:@"A" mask:SunPadButtonA];
    [self addButton:@"B" mask:SunPadButtonB];
    [self addButton:@"X" mask:SunPadButtonX];
    [self addButton:@"Y" mask:SunPadButtonY];
    [self addButton:@"Z" mask:SunPadButtonZ];
    [self addButton:@"START" mask:SunPadButtonStart];
    [self addButton:@"L" mask:SunPadButtonL];
    [self addButton:@"R" mask:SunPadButtonR];
    // D-pad
    [self addButton:@"▲" mask:SunPadButtonDpadUp];
    [self addButton:@"▼" mask:SunPadButtonDpadDown];
    [self addButton:@"◀" mask:SunPadButtonDpadLeft];
    [self addButton:@"▶" mask:SunPadButtonDpadRight];
}

- (SunPadStickView *)makeStick {
    SunPadStickView *stick = [[SunPadStickView alloc] initWithFrame:CGRectMake(0, 0, 128, 128)];
    __weak SunPadGameOverlay *weakSelf = self;
    stick.valueChanged = ^(float x, float y) {
        [weakSelf stickChanged:stick x:x y:y];
    };
    return stick;
}

- (void)addButton:(NSString *)label mask:(uint16_t)mask {
    SunPadGameButton *button = [SunPadGameButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:label forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    button.layer.cornerRadius = 28.0;
    button.layer.borderWidth = 2.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.36].CGColor;
    button.accessibilityLabel = label;
    button.inputMask = mask;
    [button addTarget:self action:@selector(buttonDown:)
     forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonUp:)
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                            UIControlEventTouchCancel];
    [_buttons addObject:button];
    [self addSubview:button];
}

- (void)stickChanged:(SunPadStickView *)stick x:(float)x y:(float)y {
    if ([SunPadSettings sharedSettings].editingControlLayout)
        return;
    int8_t xi = (int8_t)std::lround(x * 127.0f);
    int8_t yi = (int8_t)std::lround(y * 127.0f);
    if (stick == _moveStick) {
        _touchState.stickX = xi;
        _touchState.stickY = yi;
    } else {
        _touchState.cStickX = xi;
        _touchState.cStickY = yi;
    }
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)buttonDown:(SunPadGameButton *)button {
    if ([SunPadSettings sharedSettings].editingControlLayout)
        return;
    _touchState.buttons |= button.inputMask;
    if (button.inputMask == SunPadButtonL)
        _touchState.triggerL = 255;
    if (button.inputMask == SunPadButtonR)
        _touchState.triggerR = 255;
    button.transform = CGAffineTransformMakeScale(0.92, 0.92);
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)buttonUp:(SunPadGameButton *)button {
    if ([SunPadSettings sharedSettings].editingControlLayout)
        return;
    _touchState.buttons &= ~button.inputMask;
    if (button.inputMask == SunPadButtonL)
        _touchState.triggerL = 0;
    if (button.inputMask == SunPadButtonR)
        _touchState.triggerR = 0;
    button.transform = CGAffineTransformIdentity;
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)clearTouchInput {
    _touchState = (SunPadInputState){0};
    [[SunPadInputMixer sharedMixer] clearInputFromTouch:YES];
    for (SunPadGameButton *button in _buttons)
        button.transform = CGAffineTransformIdentity;
    [_moveStick reset];
    [_cStick reset];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = self.bounds;
    if (@available(iOS 11.0, *)) {
        safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
    }
    // BellPad's landscape layout math: scale to a reference 800x380 area on
    // phones and a fixed larger set on iPads (width >= 1000).
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
               safe.size.width >= 1000.0;
    CGFloat baseScale = pad ? 1.0
                            : std::min<CGFloat>(1.0, std::min(safe.size.width / 800.0,
                                                              safe.size.height / 380.0));
    CGFloat controlScale = [SunPadSettings sharedSettings].controlSizeScale;
    CGFloat scale = baseScale * controlScale;
    CGFloat margin = pad ? 34.0 : std::max<CGFloat>(8.0, 18.0 * baseScale);
    CGFloat stick = (pad ? 172.0 : 126.0 * baseScale) * controlScale;
    CGFloat small = (pad ? 62.0 : 46.0 * baseScale) * controlScale;
    CGFloat medium = (pad ? 76.0 : 58.0 * baseScale) * controlScale;
    CGFloat large = (pad ? 104.0 : 78.0 * baseScale) * controlScale;

    [self placeControl:_moveStick
          defaultFrame:CGRectMake(CGRectGetMinX(safe) + margin,
                                  CGRectGetMaxY(safe) - stick - margin, stick, stick)
            identifier:@"move"];
    CGFloat camera = (pad ? 112.0 : 86.0 * baseScale) * controlScale;
    [self placeControl:_cStick
          defaultFrame:CGRectMake(CGRectGetMaxX(safe) - margin - camera,
                                  CGRectGetMaxY(safe) - margin - camera, camera, camera)
            identifier:@"c"];

    SunPadGameButton *a = [self buttonWithMask:SunPadButtonA];
    SunPadGameButton *b = [self buttonWithMask:SunPadButtonB];
    SunPadGameButton *x = [self buttonWithMask:SunPadButtonX];
    SunPadGameButton *y = [self buttonWithMask:SunPadButtonY];
    [self placeControl:a
          defaultFrame:CGRectMake(CGRectGetMaxX(safe) - margin - large,
                                  CGRectGetMaxY(safe) - margin - camera - large - 18.0 * scale,
                                  large, large)
            identifier:@"A"];
    [self placeControl:b
          defaultFrame:CGRectMake(CGRectGetMinX(a.frame) - medium - 12.0 * scale,
                                  CGRectGetMidY(a.frame) + 8.0, medium, medium)
            identifier:@"B"];
    [self placeControl:x
          defaultFrame:CGRectMake(CGRectGetMidX(a.frame) - small * 0.5,
                                  CGRectGetMinY(a.frame) - small - 10.0 * scale,
                                  small, small)
            identifier:@"X"];
    [self placeControl:y
          defaultFrame:CGRectMake(CGRectGetMinX(a.frame) - small - 8.0 * scale,
                                  CGRectGetMinY(a.frame) - small + 8.0, small, small)
            identifier:@"Y"];

    CGFloat shoulderWidth = (pad ? 132.0 : 94.0 * baseScale) * controlScale;
    CGFloat shoulderY = CGRectGetMinY(safe) + (pad ? 92.0 : 68.0 * baseScale);
    [self placeControl:[self buttonWithMask:SunPadButtonL]
          defaultFrame:CGRectMake(CGRectGetMinX(safe) + margin, shoulderY, shoulderWidth, small)
            identifier:@"L"];
    [self placeControl:[self buttonWithMask:SunPadButtonR]
          defaultFrame:CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth, shoulderY,
                                  shoulderWidth, small)
            identifier:@"R"];
    [self placeControl:[self buttonWithMask:SunPadButtonZ]
          defaultFrame:CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth - small - 12.0 * scale,
                                  shoulderY, small, small)
            identifier:@"Z"];
    CGFloat startWidth = (pad ? 116.0 : 92.0 * baseScale) * controlScale;
    [self placeControl:[self buttonWithMask:SunPadButtonStart]
          defaultFrame:CGRectMake(CGRectGetMidX(safe) - startWidth * 0.5,
                                  CGRectGetMinY(safe) + margin, startWidth, small)
            identifier:@"Start"];

    CGFloat d = (pad ? 48.0 : 36.0 * baseScale) * controlScale;
    CGFloat dx = CGRectGetMaxX(_moveStick.frame) + (pad ? 34.0 : 18.0 * scale);
    CGFloat dy = CGRectGetMidY(_moveStick.frame) - d * 0.5;
    [self placeControl:[self buttonWithMask:SunPadButtonDpadUp]
          defaultFrame:CGRectMake(dx + d, dy - d, d, d) identifier:@"D_U"];
    [self placeControl:[self buttonWithMask:SunPadButtonDpadDown]
          defaultFrame:CGRectMake(dx + d, dy + d, d, d) identifier:@"D_D"];
    [self placeControl:[self buttonWithMask:SunPadButtonDpadLeft]
          defaultFrame:CGRectMake(dx, dy, d, d) identifier:@"D_L"];
    [self placeControl:[self buttonWithMask:SunPadButtonDpadRight]
          defaultFrame:CGRectMake(dx + 2.0 * d, dy, d, d) identifier:@"D_R"];

    for (SunPadGameButton *button in _buttons) {
        button.layer.cornerRadius =
            std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }

    CGFloat settingsSide = 40.0;
    _menuButton.frame = CGRectMake(CGRectGetMaxX(safe) - settingsSide,
                                   CGRectGetMinY(safe) + 8.0,
                                   settingsSide, settingsSide);

    CGFloat alpha = _touchControlsHidden ? 0.0 : [SunPadSettings sharedSettings].controlOpacity;
    for (UIView *view in self.subviews) {
        if (view == _menuButton || view == _settingsPanel)
            continue;
        view.alpha = alpha;
    }

    [self layoutSettingsPanelInSafeArea:safe];
}

- (void)placeControl:(UIView *)control defaultFrame:(CGRect)defaultFrame identifier:(NSString *)identifier {
    control.bounds = CGRectMake(0, 0, defaultFrame.size.width, defaultFrame.size.height);
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:@"SunPadControlOrigins"];
    NSValue *savedPoint = saved[identifier];
    if (savedPoint != nil) {
        CGPoint normalized = savedPoint.CGPointValue;
        CGRect safe = self.bounds;
        if (@available(iOS 11.0, *))
            safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
        CGFloat cx = CGRectGetMinX(safe) + normalized.x * safe.size.width;
        CGFloat cy = CGRectGetMinY(safe) + normalized.y * safe.size.height;
        CGFloat halfW = control.bounds.size.width * 0.5;
        CGFloat halfH = control.bounds.size.height * 0.5;
        cx = std::clamp(cx, CGRectGetMinX(safe) + halfW, CGRectGetMaxX(safe) - halfW);
        cy = std::clamp(cy, CGRectGetMinY(safe) + halfH, CGRectGetMaxY(safe) - halfH);
        control.center = CGPointMake(cx, cy);
    } else {
        control.center = CGPointMake(CGRectGetMidX(defaultFrame), CGRectGetMidY(defaultFrame));
    }
}

- (SunPadGameButton *)buttonWithMask:(uint16_t)mask {
    for (SunPadGameButton *button in _buttons) {
        if (button.inputMask == mask)
            return button;
    }
    return nil;
}

- (void)layoutSettingsPanelInSafeArea:(CGRect)safe {
    CGFloat width = MIN(360.0, CGRectGetWidth(safe) - 32.0);
    CGFloat height = MIN(430.0, CGRectGetHeight(safe) * 0.62);
    _settingsPanel.frame = CGRectMake(CGRectGetMidX(safe) - width * 0.5,
                                      CGRectGetMaxY(safe) - height - 16.0,
                                      width, height);
}

#pragma mark - Settings panel

- (void)buildSettingsPanel {
    _settingsPanel = [UIView new];
    _settingsPanel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _settingsPanel.layer.cornerRadius = 16.0;
    _settingsPanel.layer.borderWidth = 1.0;
    _settingsPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    _settingsPanel.hidden = YES;
    [self addSubview:_settingsPanel];

    UILabel *title = [UILabel new];
    title.text = @"Touch Control Settings";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];

    _renderScaleControl = [[UISegmentedControl alloc] initWithItems:@[@"Native", @"1×", @"2×", @"3×", @"4×"]];
    _renderScaleControl.selectedSegmentIndex = [SunPadSettings sharedSettings].renderScale;
    _renderScaleControl.accessibilityLabel = @"Render resolution";
    [_renderScaleControl addTarget:self action:@selector(renderScaleChanged:)
                  forControlEvents:UIControlEventValueChanged];

    _opacitySlider = [UISlider new];
    _opacitySlider.minimumValue = 0.25;
    _opacitySlider.maximumValue = 1.0;
    _opacitySlider.value = [SunPadSettings sharedSettings].controlOpacity;
    _opacitySlider.accessibilityLabel = @"Control opacity";
    [_opacitySlider addTarget:self action:@selector(opacityChanged:)
             forControlEvents:UIControlEventValueChanged];

    _sizeSlider = [UISlider new];
    _sizeSlider.minimumValue = 0.70;
    _sizeSlider.maximumValue = 1.35;
    _sizeSlider.value = [SunPadSettings sharedSettings].controlSizeScale;
    _sizeSlider.accessibilityLabel = @"Control size";
    [_sizeSlider addTarget:self action:@selector(sizeChanged:)
          forControlEvents:UIControlEventValueChanged];

    _hideControlsSwitch = [UISwitch new];
    _hideControlsSwitch.on = [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected;
    _hideControlsSwitch.accessibilityLabel = @"Hide touch controls when controller connected";
    [_hideControlsSwitch addTarget:self action:@selector(hideChanged:)
                  forControlEvents:UIControlEventValueChanged];

    _editLayoutSwitch = [UISwitch new];
    _editLayoutSwitch.on = [SunPadSettings sharedSettings].editingControlLayout;
    _editLayoutSwitch.accessibilityLabel = @"Move touch controls";
    [_editLayoutSwitch addTarget:self action:@selector(editLayoutChanged:)
                forControlEvents:UIControlEventValueChanged];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Reset This Device Layout" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    reset.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.88];
    reset.layer.cornerRadius = 10.0;
    [reset addTarget:self action:@selector(confirmResetLayout)
    forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title,
        [self settingsRowWithTitle:@"Render" control:_renderScaleControl],
        [self settingsRowWithTitle:@"Opacity" control:_opacitySlider],
        [self settingsRowWithTitle:@"Size" control:_sizeSlider],
        [self settingsRowWithTitle:@"Hide on controller" control:_hideControlsSwitch],
        [self settingsRowWithTitle:@"Move controls" control:_editLayoutSwitch],
        reset,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsPanel addSubview:scroll];
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_settingsPanel.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_settingsPanel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-8.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32.0],
        [reset.heightAnchor constraintEqualToConstant:40.0],
    ]];
}

- (UIView *)settingsRowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *label = [UILabel new];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [control setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12.0;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (void)toggleSettingsPanel {
    _settingsPanel.hidden = !_settingsPanel.hidden;
    if (!_settingsPanel.hidden)
        _renderScaleControl.selectedSegmentIndex = [SunPadSettings sharedSettings].renderScale;
}

- (void)renderScaleChanged:(UISegmentedControl *)control {
    [SunPadSettings sharedSettings].renderScale = control.selectedSegmentIndex;
    [[SunPadSettings sharedSettings] synchronize];
    [self refreshMenuButton];
}

- (void)opacityChanged:(UISlider *)slider {
    [SunPadSettings sharedSettings].controlOpacity = slider.value;
    [[SunPadSettings sharedSettings] synchronize];
    [self setNeedsLayout];
}

- (void)sizeChanged:(UISlider *)slider {
    [SunPadSettings sharedSettings].controlSizeScale = slider.value;
    [[SunPadSettings sharedSettings] synchronize];
    [self setNeedsLayout];
}

- (void)hideChanged:(UISwitch *)switcher {
    [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected = switcher.on;
    [[SunPadSettings sharedSettings] synchronize];
    [self applyControllerVisibility];
}

- (void)editLayoutChanged:(UISwitch *)switcher {
    [SunPadSettings sharedSettings].editingControlLayout = switcher.on;
    [[SunPadSettings sharedSettings] synchronize];
    if (switcher.on)
        [self beginLayoutEditing];
    else
        [self endLayoutEditing];
}

- (void)confirmResetLayout {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Reset Touch Control Layout?"
                                            message:@"All control positions and sizes return to their defaults."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf resetLayout];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)resetLayout {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"SunPadControlOrigins"];
    [defaults removeObjectForKey:@"SunPadControlSizeScale"];
    [defaults removeObjectForKey:@"SunPadControlOpacity"];
    [[SunPadSettings sharedSettings] synchronize];
    [self applySettings];
    [self setNeedsLayout];
}

#pragma mark - Layout editing (drag + persist)

- (void)beginLayoutEditing {
    NSArray<NSString *> *identifiers = @[
        @"move", @"c", @"A", @"B", @"X", @"Y", @"Z", @"Start", @"L", @"R",
        @"D_U", @"D_D", @"D_L", @"D_R",
    ];
    for (NSString *identifier in identifiers) {
        UIView *control = [self controlForIdentifier:identifier];
        if (control == nil)
            continue;
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(controlDragged:)];
        drag.delegate = self;
        [control addGestureRecognizer:drag];
        _controlDrags[identifier] = drag;
        _controlOrigins[identifier] = [NSValue valueWithCGPoint:control.center];
    }
}

- (void)endLayoutEditing {
    for (UIPanGestureRecognizer *drag in _controlDrags.allValues) {
        [drag.view removeGestureRecognizer:drag];
    }
    [_controlDrags removeAllObjects];
    [_controlOrigins removeAllObjects];
}

- (UIView *)controlForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"move"]) return _moveStick;
    if ([identifier isEqualToString:@"c"]) return _cStick;
    if ([identifier isEqualToString:@"D_U"]) return [self buttonWithMask:SunPadButtonDpadUp];
    if ([identifier isEqualToString:@"D_D"]) return [self buttonWithMask:SunPadButtonDpadDown];
    if ([identifier isEqualToString:@"D_L"]) return [self buttonWithMask:SunPadButtonDpadLeft];
    if ([identifier isEqualToString:@"D_R"]) return [self buttonWithMask:SunPadButtonDpadRight];
    for (SunPadGameButton *button in _buttons) {
        if ([identifier isEqualToString:[self identifierForMask:button.inputMask]])
            return button;
    }
    return nil;
}

- (NSString *)identifierForMask:(uint16_t)mask {
    switch (mask) {
    case SunPadButtonA: return @"A";
    case SunPadButtonB: return @"B";
    case SunPadButtonX: return @"X";
    case SunPadButtonY: return @"Y";
    case SunPadButtonZ: return @"Z";
    case SunPadButtonStart: return @"Start";
    case SunPadButtonL: return @"L";
    case SunPadButtonR: return @"R";
    case SunPadButtonDpadUp: return @"D_U";
    case SunPadButtonDpadDown: return @"D_D";
    case SunPadButtonDpadLeft: return @"D_L";
    case SunPadButtonDpadRight: return @"D_R";
    default: return @"";
    }
}

- (void)controlDragged:(UIPanGestureRecognizer *)drag {
    NSString *identifier = nil;
    for (NSString *key in _controlDrags.allKeys) {
        if (_controlDrags[key] == drag) {
            identifier = key;
            break;
        }
    }
    if (identifier == nil)
        return;
    CGPoint translation = [drag translationInView:self];
    NSValue *originValue = _controlOrigins[identifier];
    if (originValue == nil)
        return;
    CGPoint origin = originValue.CGPointValue;
    drag.view.center = CGPointMake(origin.x + translation.x, origin.y + translation.y);

    if (drag.state == UIGestureRecognizerStateEnded ||
        drag.state == UIGestureRecognizerStateCancelled) {
        CGRect safe = self.bounds;
        if (@available(iOS 11.0, *))
            safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
        CGPoint normalized = CGPointMake(
            (drag.view.center.x - CGRectGetMinX(safe)) / safe.size.width,
            (drag.view.center.y - CGRectGetMinY(safe)) / safe.size.height);
        NSMutableDictionary *saved = [[[NSUserDefaults standardUserDefaults]
            dictionaryForKey:@"SunPadControlOrigins"] mutableCopy];
        if (saved == nil)
            saved = [NSMutableDictionary dictionary];
        saved[identifier] = [NSValue valueWithCGPoint:normalized];
        [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"SunPadControlOrigins"];
        [[SunPadSettings sharedSettings] synchronize];
    }
}

#pragma mark - Settings application

- (void)applySettings {
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    _renderScaleControl.selectedSegmentIndex = settings.renderScale;
    _opacitySlider.value = settings.controlOpacity;
    _sizeSlider.value = settings.controlSizeScale;
    _hideControlsSwitch.on = settings.hideTouchControlsWhenControllerConnected;
    _editLayoutSwitch.on = settings.editingControlLayout;
    [self setNeedsLayout];
}

- (void)setTouchControlsHidden:(BOOL)hidden animated:(BOOL)animated {
    _touchControlsHidden = hidden;
    [UIView animateWithDuration:animated ? 0.25 : 0.0 animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];
}

- (void)applyControllerVisibility {
    BOOL controllerConnected = NO;
#if !TARGET_OS_SIMULATOR
    // Only real hardware controllers hide the touch controls; the Simulator
    // can report virtual controllers that would hide them during testing.
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            controllerConnected = YES;
            break;
        }
    }
#endif
    BOOL shouldHide = controllerConnected &&
        [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected;
    [self setTouchControlsHidden:shouldHide animated:YES];
    if (controllerConnected)
        [self clearTouchInput];
}

- (void)observeControllerConnection {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyControllerVisibility)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyControllerVisibility)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    [self applyControllerVisibility];
}

@end
