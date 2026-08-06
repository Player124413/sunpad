#import "SunPadGameOverlay.h"

#import "SunPadSettings.h"

#import <GameController/GameController.h>

#include <algorithm>

@interface SunPadStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@end

@implementation SunPadStickView {
    UIView *_thumb;
    float _valueX, _valueY;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
        self.layer.borderWidth = 2.0;
        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.30];
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

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _valueX = _valueY = 0.0f;
    [self updateThumbCenter];
    if (self.valueChanged)
        self.valueChanged(0.0f, 0.0f);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _valueX = _valueY = 0.0f;
    [self updateThumbCenter];
    if (self.valueChanged)
        self.valueChanged(0.0f, 0.0f);
}

- (void)handleTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat half = self.bounds.size.width * 0.5;
    CGFloat maxTravel = half - _thumb.bounds.size.width * 0.5 - 3.0;
    if (maxTravel <= 0.0f)
        return;
    float x = std::max(-1.0f, std::min(1.0f, (float)((p.x - half) / maxTravel)));
    float y = std::max(-1.0f, std::min(1.0f, (float)((p.y - half) / maxTravel)));
    _valueX = x;
    _valueY = y;
    [self updateThumbCenter];
    if (self.valueChanged)
        self.valueChanged(x, y);
}

@end

@interface SunPadButtonView : UIButton
@property(nonatomic, assign) BOOL padHeld;
@end

@implementation SunPadButtonView
@end

@interface SunPadGameOverlay () <UIGestureRecognizerDelegate>
@end

@implementation SunPadGameOverlay {
    UIButton *_menuButton;          // the three-dot menu
    SunPadStickView *_moveStick;
    SunPadStickView *_cStick;
    NSMutableDictionary<NSString *, SunPadButtonView *> *_buttons;
    NSMutableDictionary<NSString *, UIPanGestureRecognizer *> *_controlDrags;
    NSMutableDictionary<NSString *, NSValue *> *_controlOrigins;

    UIView *_settingsPanel;
    UISegmentedControl *_renderScaleControl;
    UISlider *_opacitySlider;
    UISlider *_sizeSlider;
    UISwitch *_hideControlsSwitch;
    UISwitch *_editLayoutSwitch;

    SunPadInputState _input;
    BOOL _touchControlsHidden;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        _input.connected = 1;
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
        [[SunPadSettings sharedSettings] synchronize];
        [weakSelf.delegate gameOverlayRequestsGameDataChange:weakSelf];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Touch controls

- (void)buildTouchControls {
    _buttons = [NSMutableDictionary dictionary];
    _controlDrags = [NSMutableDictionary dictionary];
    _controlOrigins = [NSMutableDictionary dictionary];

    _moveStick = [self makeStick];
    _cStick = [self makeStick];
    [self addSubview:_moveStick];
    [self addSubview:_cStick];

    NSArray<NSArray<NSString *> *> *buttonSpecs = @[
        @[ @"A", @"A" ],
        @[ @"B", @"B" ],
        @[ @"X", @"X" ],
        @[ @"Y", @"Y" ],
        @[ @"Z", @"Z" ],
        @[ @"Start", @"START" ],
        @[ @"L", @"L" ],
        @[ @"R", @"R" ],
    ];
    for (NSArray<NSString *> *spec in buttonSpecs) {
        NSString *identifier = spec[0];
        NSString *label = spec[1];
        SunPadButtonView *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:label forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
        button.layer.cornerRadius = 28.0;
        button.layer.borderWidth = 2.0;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.36].CGColor;
        button.accessibilityLabel = label;
        [button addTarget:self action:@selector(buttonDown:)
         forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(buttonUp:)
         forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                UIControlEventTouchCancel];
        _buttons[identifier] = button;
        [self addSubview:button];
    }
}

- (SunPadStickView *)makeStick {
    SunPadStickView *stick = [[SunPadStickView alloc] initWithFrame:CGRectMake(0, 0, 128, 128)];
    __weak SunPadGameOverlay *weakSelf = self;
    stick.valueChanged = ^(float x, float y) {
        [weakSelf stickChanged:stick x:x y:y];
    };
    return stick;
}

- (void)stickChanged:(SunPadStickView *)stick x:(float)x y:(float)y {
    if (stick == _moveStick) {
        _input.mainX = x;
        _input.mainY = y;
    } else {
        _input.cX = x;
        _input.cY = y;
    }
    [self publishInput];
}

- (void)buttonDown:(SunPadButtonView *)button {
    button.padHeld = YES;
    [self setButton:button pressed:YES];
}

- (void)buttonUp:(SunPadButtonView *)button {
    button.padHeld = NO;
    [self setButton:button pressed:NO];
}

- (void)setButton:(SunPadButtonView *)button pressed:(BOOL)pressed {
    NSArray<NSString *> *matches =
        [_buttons.allKeys filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return _buttons[object] == button;
            }]];
    NSString *identifier = matches.firstObject;
    if (identifier == nil)
        return;
    SunPadButton bit = SunPadButtonA;
    if ([identifier isEqualToString:@"A"]) bit = SunPadButtonA;
    else if ([identifier isEqualToString:@"B"]) bit = SunPadButtonB;
    else if ([identifier isEqualToString:@"X"]) bit = SunPadButtonX;
    else if ([identifier isEqualToString:@"Y"]) bit = SunPadButtonY;
    else if ([identifier isEqualToString:@"Z"]) bit = SunPadButtonZ;
    else if ([identifier isEqualToString:@"Start"]) bit = SunPadButtonStart;
    else if ([identifier isEqualToString:@"L"]) bit = SunPadButtonL;
    else if ([identifier isEqualToString:@"R"]) bit = SunPadButtonR;
    if (pressed)
        _input.buttons |= bit;
    else
        _input.buttons &= ~bit;
    [self publishInput];
}

- (void)publishInput {
    [self.delegate gameOverlay:self didUpdateInput:_input];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = self.bounds;
    if (@available(iOS 11.0, *)) {
        safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
    }

    CGFloat margin = 16.0;
    CGFloat scale = [SunPadSettings sharedSettings].controlSizeScale;
    _menuButton.frame = CGRectMake(CGRectGetMaxX(safe) - margin - 44.0,
                                   CGRectGetMinY(safe) + margin, 44.0, 44.0);

    CGFloat stickSize = 128.0 * scale;
    _moveStick.frame = CGRectMake(CGRectGetMinX(safe) + margin,
                                  CGRectGetMaxY(safe) - margin - stickSize,
                                  stickSize, stickSize);
    _cStick.frame = CGRectMake(CGRectGetMidX(safe) - stickSize * 0.5,
                               CGRectGetMaxY(safe) - margin - stickSize,
                               stickSize, stickSize);

    CGFloat buttonSize = 56.0 * scale;
    CGFloat smallSize = 44.0 * scale;
    CGFloat gap = 8.0 * scale;
    SunPadButtonView *a = _buttons[@"A"];
    SunPadButtonView *b = _buttons[@"B"];
    SunPadButtonView *x = _buttons[@"X"];
    SunPadButtonView *y = _buttons[@"Y"];
    SunPadButtonView *z = _buttons[@"Z"];
    SunPadButtonView *start = _buttons[@"Start"];
    SunPadButtonView *l = _buttons[@"L"];
    SunPadButtonView *r = _buttons[@"R"];

    CGFloat rightX = CGRectGetMaxX(safe) - margin - buttonSize;
    CGFloat rightY = CGRectGetMaxY(safe) - margin - buttonSize;
    a.frame = CGRectMake(rightX, rightY, buttonSize, buttonSize);
    b.frame = CGRectMake(CGRectGetMinX(a.frame) - buttonSize - gap,
                         CGRectGetMidY(a.frame) + 8.0, buttonSize, buttonSize);
    x.frame = CGRectMake(CGRectGetMidX(a.frame) - smallSize * 0.5,
                         CGRectGetMinY(a.frame) - smallSize - 10.0 * scale,
                         smallSize, smallSize);
    y.frame = CGRectMake(CGRectGetMinX(a.frame) - smallSize - 8.0 * scale,
                         CGRectGetMinY(a.frame) - smallSize + 8.0,
                         smallSize, smallSize);
    z.frame = CGRectMake(CGRectGetMinX(a.frame) - smallSize - 8.0 * scale,
                         CGRectGetMaxY(a.frame) - smallSize, smallSize, smallSize);
    start.frame = CGRectMake(CGRectGetMinX(a.frame) - smallSize * 0.5,
                             CGRectGetMaxY(a.frame) + 10.0 * scale,
                             smallSize, 30.0 * scale);

    CGFloat shoulderY = CGRectGetMinY(safe) + margin + 44.0 + 12.0;
    CGFloat shoulderWidth = 74.0 * scale;
    l.frame = CGRectMake(CGRectGetMinX(safe) + margin, shoulderY,
                         shoulderWidth, 36.0 * scale);
    r.frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth, shoulderY,
                         shoulderWidth, 36.0 * scale);

    if (_touchControlsHidden) {
        for (UIView *view in self.subviews) {
            if (view == _menuButton || view == _settingsPanel)
                continue;
            view.alpha = 0.0;
        }
    } else {
        for (UIView *view in self.subviews) {
            if (view == _menuButton || view == _settingsPanel)
                continue;
            view.alpha = [SunPadSettings sharedSettings].controlOpacity;
        }
    }

    [self layoutSettingsPanelInSafeArea:safe];
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
    if (!_settingsPanel.hidden) {
        _renderScaleControl.selectedSegmentIndex = [SunPadSettings sharedSettings].renderScale;
    }
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
    [defaults removeObjectForKey:@"SunPadControlSizeScale"];
    [defaults removeObjectForKey:@"SunPadControlOpacity"];
    [defaults removeObjectForKey:@"SunPadControlOrigins"];
    [defaults removeObjectForKey:@"SunPadControlSizeOverrides"];
    [[SunPadSettings sharedSettings] synchronize];
    _controlOrigins = [NSMutableDictionary dictionary];
    [self applySettings];
    [self setNeedsLayout];
}

#pragma mark - Layout editing (drag controls)

- (void)beginLayoutEditing {
    for (NSString *identifier in @[ @"move", @"c", @"A", @"B", @"X", @"Y", @"Z", @"Start", @"L", @"R" ]) {
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
        UIView *control = drag.view;
        [control removeGestureRecognizer:drag];
    }
    [_controlDrags removeAllObjects];
    [_controlOrigins removeAllObjects];
}

- (UIView *)controlForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"move"]) return _moveStick;
    if ([identifier isEqualToString:@"c"]) return _cStick;
    return _buttons[identifier];
}

- (void)controlDragged:(UIPanGestureRecognizer *)drag {
    NSString *identifier = [_controlDrags.allKeys filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return _controlDrags[object] == drag;
        }]].firstObject;
    if (identifier == nil)
        return;
    CGPoint translation = [drag translationInView:self];
    NSValue *originValue = _controlOrigins[identifier];
    if (originValue == nil)
        return;
    CGPoint origin = originValue.CGPointValue;
    drag.view.center = CGPointMake(origin.x + translation.x, origin.y + translation.y);
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
    BOOL controllerConnected = GCController.controllers.count > 0;
    BOOL shouldHide = controllerConnected &&
        [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected;
    [self setTouchControlsHidden:shouldHide animated:YES];
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

- (SunPadInputState)currentInputState {
    return _input;
}

@end
