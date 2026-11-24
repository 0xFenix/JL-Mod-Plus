// UIKit host for the J2ME runtime: presents the frames delivered by the
// j2me_render flush callback and turns on-screen controls into MIDP key or
// pointer events. Rendering and input stay in the vendored runtime; this file
// only supplies the window that a person actually looks at and touches.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "jvm_bridge.h"
#include "j2me_render.h"
#include "j2me_input.h"
#include "j2me_ui.h"
#include "host_form.h"
#include "host_shell.h"
#include "host_theme.h"
#include "host_ui.h"

// ---------------------------------------------------------------- MIDP keys

#define RT_KEY_UP (-1)
#define RT_KEY_DOWN (-2)
#define RT_KEY_LEFT (-3)
#define RT_KEY_RIGHT (-4)
#define RT_KEY_FIRE (-5)
#define RT_KEY_SOFT1 (-6)
#define RT_KEY_SOFT2 (-7)

static const int rt_keypad_keys[] = {
    RT_KEY_SOFT1, RT_KEY_UP, RT_KEY_SOFT2,
    RT_KEY_LEFT, RT_KEY_FIRE, RT_KEY_RIGHT,
    '*', RT_KEY_DOWN, '#',
};

static const int rt_keypad_cols = 3;

// ------------------------------------------------------------ runtime state

static const char *g_res_root;
static const char *g_save_root;
static const char *g_midlet_jar;
static int g_width;
static int g_height;
static int g_fps_limit;

static int g_frames;
static double g_started;

static double rt_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double) ts.tv_sec + (double) ts.tv_nsec / 1e9;
}

// ---------------------------------------------------------------- game view

@interface RTGameView : UIView
@property(nonatomic) CGImageRef currentImage;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@end

@implementation RTGameView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.contentsGravity = kCAGravityResizeAspect;
        self.layer.magnificationFilter = kCAFilterNearest;
        self.layer.minificationFilter = kCAFilterNearest;
        self.multipleTouchEnabled = NO;
        _canvasWidth = 240;
        _canvasHeight = 320;
    }
    return self;
}

- (void)setCurrentImage:(CGImageRef)image {
    if (_currentImage) {
        CGImageRelease(_currentImage);
    }
    _currentImage = image ? CGImageRetain(image) : NULL;
    self.layer.contents = (__bridge id) _currentImage;
}

- (void)dealloc {
    if (_currentImage) {
        CGImageRelease(_currentImage);
    }
}

- (void)postTouch:(UITouch *)touch type:(int)type {
    CGSize bounds = self.bounds.size;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    float scale = MIN(bounds.width / (float) self.canvasWidth,
                      bounds.height / (float) self.canvasHeight);
    float shownW = self.canvasWidth * scale;
    float shownH = self.canvasHeight * scale;
    CGPoint p = [touch locationInView:self];
    float x = (p.x - (bounds.width - shownW) / 2.0f) / scale;
    float y = (p.y - (bounds.height - shownH) / 2.0f) / scale;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x > self.canvasWidth - 1) x = self.canvasWidth - 1;
    if (y > self.canvasHeight - 1) y = self.canvasHeight - 1;
    j2me_input_post_touch(type, (int) x, (int) y);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) [self postTouch:t type:J2ME_INPUT_POINTER_PRESSED];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) [self postTouch:t type:J2ME_INPUT_POINTER_DRAGGED];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) [self postTouch:t type:J2ME_INPUT_POINTER_RELEASED];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) [self postTouch:t type:J2ME_INPUT_POINTER_RELEASED];
}

@end

// ------------------------------------------------------------------ keypad

@interface RTKeyButton : UIButton
@property(nonatomic) int midpKeyCode;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UIImageView *symbolView;
@end

@implementation RTKeyButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = rt_color_surface_raised();
        self.layer.cornerRadius = 14.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

        UIImageView *symbol = [[UIImageView alloc] init];
        symbol.translatesAutoresizingMaskIntoConstraints = NO;
        symbol.contentMode = UIViewContentModeScaleAspectFit;
        symbol.tintColor = rt_color_text_primary();
        [self addSubview:symbol];
        self.symbolView = symbol;

        UILabel *sub = [[UILabel alloc] init];
        sub.translatesAutoresizingMaskIntoConstraints = NO;
        sub.textAlignment = NSTextAlignmentCenter;
        sub.textColor = rt_color_text_secondary();
        sub.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
                scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]];
        [self addSubview:sub];
        self.detailLabel = sub;

        [NSLayoutConstraint activateConstraints:@[
            [sub.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [sub.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [sub.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],

            [symbol.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:-2],
            [symbol.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [symbol.widthAnchor constraintEqualToConstant:22],
            [symbol.heightAnchor constraintEqualToConstant:22],
            [symbol.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted
            ? [rt_color_text_primary() colorWithAlphaComponent:0.14]
            : rt_color_surface_raised();
}

@end

@interface RTKeypadView : UIView
@property(nonatomic, strong) NSMutableArray<RTKeyButton *> *buttons;
@property(nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@end

@implementation RTKeypadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];

    UIStackView *column = [[UIStackView alloc] init];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.axis = UILayoutConstraintAxisVertical;
    column.distribution = UIStackViewDistributionFillEqually;
    column.spacing = 8;
    [self addSubview:column];

    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [column.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
    ]];

    self.buttons = [NSMutableArray array];
    NSDictionary *symbols = @{
        @(-1): @"chevron.up",
        @(-2): @"chevron.down",
        @(-3): @"chevron.left",
        @(-4): @"chevron.right",
        @(-5): @"",
        @(-6): @"chevron.left",
        @(-7): @"chevron.right",
    };

    int total = (int) (sizeof(rt_keypad_keys) / sizeof(rt_keypad_keys[0]));
    for (int row = 0; row * rt_keypad_cols < total; row++) {
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        line.spacing = 8;

        for (int col = 0; col < rt_keypad_cols; col++) {
            int index = row * rt_keypad_cols + col;
            int key = rt_keypad_keys[index];
            RTKeyButton *button = [[RTKeyButton alloc] initWithFrame:CGRectZero];
            button.midpKeyCode = key;
            button.translatesAutoresizingMaskIntoConstraints = NO;
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;

            if (key == RT_KEY_FIRE) {
                button.backgroundColor = rt_color_accent();
                [button setTitle:@"OK" forState:UIControlStateNormal];
                [button setTitleColor:rt_color_ink() forState:UIControlStateNormal];
                button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                        scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightBold]];
                button.detailLabel.hidden = YES;
                button.symbolView.hidden = YES;
            } else if (key == RT_KEY_SOFT1 || key == RT_KEY_SOFT2) {
                button.detailLabel.text = key == RT_KEY_SOFT1 ? @"LSK" : @"RSK";
                button.titleLabel.hidden = YES;
                button.symbolView.image = [UIImage systemImageNamed:symbols[@(key)]];
                button.symbolView.tintColor = rt_color_text_secondary();
            } else if (key == '*' || key == '#') {
                button.detailLabel.hidden = YES;
                button.symbolView.hidden = YES;
                [button setTitle:key == '*' ? @"*" : @"#" forState:UIControlStateNormal];
                [button setTitleColor:rt_color_text_primary() forState:UIControlStateNormal];
            } else {
                button.detailLabel.hidden = YES;
                button.titleLabel.hidden = YES;
                button.symbolView.image = [UIImage systemImageNamed:symbols[@(key)]];
            }

            [button addTarget:self
                        action:@selector(keyDown:)
              forControlEvents:UIControlEventTouchDown];
            [button addTarget:self
                        action:@selector(keyUp:)
              forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                               UIControlEventTouchCancel];
            [self.buttons addObject:button];
            [line addArrangedSubview:button];
        }
        [column addArrangedSubview:line];
    }
    return self;
}

- (void)keyDown:(RTKeyButton *)button {
    [self.haptic prepare];
    [self.haptic impactOccurred];
    j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, button.midpKeyCode);
}

- (void)keyUp:(RTKeyButton *)button {
    j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, button.midpKeyCode);
}

@end

// ------------------------------------------------------------ game sessions

@interface RTGameSession : NSObject
@property(nonatomic) int slot;
@property(nonatomic, copy) NSString *jarPath;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) int fpsLimit;
@property(nonatomic) BOOL running;
@property(nonatomic) CGImageRef lastImage;
@end

@implementation RTGameSession

- (void)setLastImage:(CGImageRef)image {
    if (_lastImage) {
        CGImageRelease(_lastImage);
    }
    _lastImage = image;
}

- (void)dealloc {
    if (_lastImage) {
        CGImageRelease(_lastImage);
    }
}

@end

@interface RTViewController : UIViewController
@property(nonatomic, strong) RTGameView *gameView;
@property(nonatomic, strong) UIView *canvasContainer;
@property(nonatomic, strong) UIView *statusPill;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIView *topBar;
@property(nonatomic, strong) UIVisualEffectView *topBarBlur;
@property(nonatomic, strong) UIView *topBarTint;
@property(nonatomic, strong) UIView *topBarRule;
@property(nonatomic, strong) NSLayoutConstraint *topBarHeight;
@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *fpsButton;
@property(nonatomic, strong) UIScrollView *tabScroll;
@property(nonatomic, strong) UIStackView *tabStack;
/// Two placements for the tab strip: beside the title for one game, and using
/// the whole bar once tabs need the room.
@property(nonatomic, strong) NSLayoutConstraint *tabLeadingToTitle;
@property(nonatomic, strong) NSLayoutConstraint *tabLeadingToBack;
@property(nonatomic, strong) UIView *keypadContainer;
@property(nonatomic, strong) RTKeypadView *keypad;
@property(nonatomic, strong) NSMutableArray<RTGameSession *> *sessions;
@property(nonatomic) int focusedSlot;
@property(nonatomic) BOOL midletStarted;
@property(nonatomic) BOOL showsFPS;
@property(nonatomic, copy) NSString *jarPath;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@property(nonatomic) int fpsLimit;
@property(nonatomic) BOOL showsBackButton;
@end

static RTViewController *g_controller = nil;

/// A MIDP screen replaces the canvas with buttons of its own, so the pad is
/// retired while a panel is up instead of peeking out around it.
static void rt_set_keypad_visible(int visible) {
    RTViewController *controller = g_controller;
    if (!controller) return;
    controller.keypadContainer.hidden = visible != 0;
    controller.statusPill.hidden = visible != 0;
}
static NSString *const RTShowFPSDefaultsKey = @"RTShowFPS";
static int g_slot_frames[JVM_BRIDGE_MAX_SLOTS];
static double g_slot_started[JVM_BRIDGE_MAX_SLOTS];

@implementation RTViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableArray array];
        _focusedSlot = -1;
        _showsFPS = [[NSUserDefaults standardUserDefaults] boolForKey:RTShowFPSDefaultsKey];
    }
    return self;
}

- (RTGameSession *)sessionForSlot:(int)slot {
    for (RTGameSession *session in self.sessions) {
        if (session.slot == slot) {
            return session;
        }
    }
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = rt_color_ink();
    self.navigationItem.hidesBackButton = YES;

    // Top bar
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBar.clipsToBounds = YES;
    [self.view addSubview:self.topBar];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    self.topBarBlur = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.topBarBlur.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.topBarBlur];

    self.topBarTint = [[UIView alloc] init];
    self.topBarTint.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBarTint.backgroundColor = [rt_color_ink() colorWithAlphaComponent:0.92];
    [self.topBar addSubview:self.topBarTint];

    self.topBarRule = [[UIView alloc] init];
    self.topBarRule.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBarRule.backgroundColor = rt_color_hairline();
    [self.topBar addSubview:self.topBarRule];

    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton setImage:[[UIImage systemImageNamed:@"chevron.left"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                     forState:UIControlStateNormal];
    self.backButton.tintColor = rt_color_accent();
    self.backButton.backgroundColor = [UIColor clearColor];
    self.backButton.accessibilityLabel = @"Thư viện";
    [self.backButton addTarget:self
                        action:@selector(closeGame:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = rt_color_text_secondary();
    self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
            scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.topBar addSubview:self.titleLabel];

    self.fpsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fpsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fpsButton setImage:[[UIImage systemImageNamed:@"speedometer"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                    forState:UIControlStateNormal];
    self.fpsButton.tintColor = self.showsFPS ? rt_color_accent() : rt_color_text_secondary();
    self.fpsButton.backgroundColor = [UIColor clearColor];
    self.fpsButton.accessibilityLabel = @"Hiện FPS";
    [self.fpsButton addTarget:self
                       action:@selector(toggleFPS:)
             forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.fpsButton];

    self.tabScroll = [[UIScrollView alloc] init];
    self.tabScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabScroll.showsHorizontalScrollIndicator = NO;
    [self.topBar addSubview:self.tabScroll];

    self.tabStack = [[UIStackView alloc] init];
    self.tabStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabStack.axis = UILayoutConstraintAxisHorizontal;
    self.tabStack.spacing = 8;
    self.tabStack.alignment = UIStackViewAlignmentCenter;
    [self.tabScroll addSubview:self.tabStack];

    // Canvas
    self.canvasContainer = [[UIView alloc] init];
    self.canvasContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvasContainer.backgroundColor = [UIColor blackColor];
    self.canvasContainer.layer.cornerRadius = 10.0;
    self.canvasContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.canvasContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.canvasContainer.layer.borderColor = rt_color_hairline().CGColor;
    self.canvasContainer.clipsToBounds = YES;
    [self.view addSubview:self.canvasContainer];

    self.gameView = [[RTGameView alloc] init];
    self.gameView.translatesAutoresizingMaskIntoConstraints = NO;
    int width = self.canvasWidth > 0 ? self.canvasWidth : g_width;
    int height = self.canvasHeight > 0 ? self.canvasHeight : g_height;
    self.gameView.canvasWidth = width;
    self.gameView.canvasHeight = height;
    [self.canvasContainer addSubview:self.gameView];

    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.backgroundColor = [rt_color_surface() colorWithAlphaComponent:0.92];
    self.statusPill.layer.cornerRadius = 11.0;
    self.statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPill.clipsToBounds = YES;
    [self.canvasContainer addSubview:self.statusPill];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = rt_color_text_secondary();
    self.statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Đang khởi động";
    [self.statusPill addSubview:self.statusLabel];

    // Keypad
    self.keypadContainer = [[UIView alloc] init];
    self.keypadContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.keypadContainer.backgroundColor = rt_color_surface();
    self.keypadContainer.layer.cornerRadius = 20.0;
    self.keypadContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.keypadContainer.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.keypadContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.keypadContainer.layer.borderColor = rt_color_hairline().CGColor;
    [self.view addSubview:self.keypadContainer];

    self.keypad = [[RTKeypadView alloc] init];
    self.keypad.translatesAutoresizingMaskIntoConstraints = NO;
    [self.keypadContainer addSubview:self.keypad];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.topBarHeight = [self.topBar.heightAnchor constraintEqualToConstant:0];
    self.tabLeadingToTitle = [self.tabScroll.leadingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor
                                                                         constant:8];
    self.tabLeadingToBack = [self.tabScroll.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor
                                                                        constant:4];
    self.tabLeadingToTitle.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        self.topBarHeight,

        [self.topBarBlur.topAnchor constraintEqualToAnchor:self.topBar.topAnchor],
        [self.topBarBlur.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [self.topBarBlur.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
        [self.topBarBlur.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],

        [self.topBarTint.topAnchor constraintEqualToAnchor:self.topBar.topAnchor],
        [self.topBarTint.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [self.topBarTint.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
        [self.topBarTint.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],

        [self.topBarRule.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [self.topBarRule.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
        [self.topBarRule.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.topBarRule.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:4],
        [self.backButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:44],
        [self.backButton.heightAnchor constraintEqualToConstant:44],

        [self.fpsButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-4],
        [self.fpsButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.fpsButton.widthAnchor constraintEqualToConstant:44],
        [self.fpsButton.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:4],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.fpsButton.leadingAnchor constant:-8],

        [self.tabScroll.topAnchor constraintEqualToAnchor:self.topBar.topAnchor constant:4],
        [self.tabScroll.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:-4],
        [self.tabScroll.trailingAnchor constraintEqualToAnchor:self.fpsButton.leadingAnchor constant:-4],

        [self.tabStack.leadingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.leadingAnchor constant:4],
        [self.tabStack.trailingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.trailingAnchor constant:-4],
        [self.tabStack.topAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.topAnchor],
        [self.tabStack.bottomAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.bottomAnchor],
        [self.tabStack.heightAnchor constraintEqualToAnchor:self.tabScroll.frameLayoutGuide.heightAnchor],

        [self.canvasContainer.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:12],
        [self.canvasContainer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.canvasContainer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],

        [self.gameView.topAnchor constraintEqualToAnchor:self.canvasContainer.topAnchor],
        [self.gameView.leadingAnchor constraintEqualToAnchor:self.canvasContainer.leadingAnchor],
        [self.gameView.trailingAnchor constraintEqualToAnchor:self.canvasContainer.trailingAnchor],
        [self.gameView.bottomAnchor constraintEqualToAnchor:self.canvasContainer.bottomAnchor],

        [self.statusPill.leadingAnchor constraintEqualToAnchor:self.canvasContainer.leadingAnchor constant:8],
        [self.statusPill.bottomAnchor constraintEqualToAnchor:self.canvasContainer.bottomAnchor constant:-8],
        [self.statusPill.heightAnchor constraintEqualToConstant:22],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:8],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-8],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusPill.topAnchor],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusPill.bottomAnchor],

        [self.keypadContainer.topAnchor constraintEqualToAnchor:self.canvasContainer.bottomAnchor],
        [self.keypadContainer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.keypadContainer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.keypadContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.keypadContainer.heightAnchor constraintEqualToConstant:190],

        [self.keypad.topAnchor constraintEqualToAnchor:self.keypadContainer.topAnchor],
        [self.keypad.leadingAnchor constraintEqualToAnchor:self.keypadContainer.leadingAnchor],
        [self.keypad.trailingAnchor constraintEqualToAnchor:self.keypadContainer.trailingAnchor],
        [self.keypad.bottomAnchor constraintEqualToAnchor:self.keypadContainer.bottomAnchor],
    ]];

    self.statusPill.hidden = NO;
    [self updateStatus];
    rt_form_ui_set_visibility_callback(rt_set_keypad_visible);
    rt_form_ui_attach((__bridge void *) self.view);
    rt_form_ui_present(j2me_ui_get_slot_active_action(self.focusedSlot >= 0 ? self.focusedSlot : 0));
    [self rebuildTabs];
}

- (void)updateStatus {
    RTGameSession *session = [self sessionForSlot:self.focusedSlot];
    if (!session) {
        self.statusLabel.text = @"Đang khởi động";
        self.statusPill.hidden = NO;
        return;
    }
    if (!session.running) {
        self.statusLabel.text = @"Đã dừng";
        self.statusPill.hidden = NO;
        return;
    }
    if (self.showsFPS && g_slot_frames[session.slot] > 0) {
        double elapsed = rt_now() - g_slot_started[session.slot];
        double fps = elapsed > 0 ? (double) g_slot_frames[session.slot] / elapsed : 0;
        self.statusLabel.text = [NSString localizedStringWithFormat:@"%.1f fps", fps];
        self.statusPill.hidden = NO;
    } else {
        self.statusPill.hidden = YES;
    }
}

- (void)toggleFPS:(UIButton *)sender {
    (void)sender;
    self.showsFPS = !self.showsFPS;
    [[NSUserDefaults standardUserDefaults] setBool:self.showsFPS forKey:RTShowFPSDefaultsKey];
    self.fpsButton.tintColor = self.showsFPS ? rt_color_accent() : rt_color_text_secondary();
    [self updateStatus];
}

- (void)rebuildTabs {
    for (UIView *view in self.tabStack.arrangedSubviews) {
        [self.tabStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (RTGameSession *session in self.sessions) {
        UIView *tab = [[UIView alloc] init];
        BOOL selected = session.slot == self.focusedSlot;
        tab.backgroundColor = selected
                ? [rt_color_accent() colorWithAlphaComponent:0.16]
                : [UIColor colorWithWhite:1.0 alpha:0.06];
        tab.layer.cornerRadius = 8.0;
        tab.layer.cornerCurve = kCACornerCurveContinuous;
        tab.clipsToBounds = YES;

        UIButton *title = [UIButton buttonWithType:UIButtonTypeCustom];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *tabTitle = session.title;
        [title setTitle:tabTitle forState:UIControlStateNormal];
        [title setTitleColor:selected ? rt_color_accent()
                                     : (session.running ? rt_color_text_secondary() : rt_color_text_tertiary())
                      forState:UIControlStateNormal];
        title.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
                scaledFontForFont:[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]];
        title.contentEdgeInsets = UIEdgeInsetsMake(4, 10, 4, 4);
        title.tag = session.slot;
        [title addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
        [tab addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        [close setImage:[[UIImage systemImageNamed:@"xmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
               forState:UIControlStateNormal];
        close.tintColor = selected ? rt_color_accent() : rt_color_text_secondary();
        close.backgroundColor = [UIColor clearColor];
        close.tag = session.slot;
        close.accessibilityLabel = @"Đóng";
        [close addTarget:self action:@selector(closeTab:) forControlEvents:UIControlEventTouchUpInside];
        [tab addSubview:close];

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:tab.leadingAnchor],
            [title.topAnchor constraintEqualToAnchor:tab.topAnchor],
            [title.bottomAnchor constraintEqualToAnchor:tab.bottomAnchor],

            [close.leadingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [close.trailingAnchor constraintEqualToAnchor:tab.trailingAnchor constant:-2],
            [close.centerYAnchor constraintEqualToAnchor:tab.centerYAnchor],
            [close.widthAnchor constraintEqualToConstant:36],
            [close.heightAnchor constraintEqualToConstant:36],
        ]];
        [self.tabStack addArrangedSubview:tab];
    }

    BOOL showBar = self.sessions.count > 1 || self.showsBackButton;
    BOOL showTabs = self.sessions.count > 1;
    self.topBar.hidden = !showBar;
    self.topBarHeight.constant = showBar ? 44 : 0;
    self.tabScroll.hidden = !showTabs;
    // With tabs on screen the focused title is redundant and steals the room
    // the strip needs, so the strip takes the space beside the back button.
    self.titleLabel.hidden = showTabs;
    self.tabLeadingToTitle.active = !showTabs;
    self.tabLeadingToBack.active = showTabs;

    RTGameSession *focused = [self sessionForSlot:self.focusedSlot];
    self.titleLabel.text = focused ? focused.title : @"";
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    NSUInteger index = 0;
    for (RTGameSession *session in self.sessions) {
        if (session.slot == self.focusedSlot) break;
        index++;
    }
    if (index < self.tabStack.arrangedSubviews.count) {
        UIView *tab = self.tabStack.arrangedSubviews[index];
        [self.tabScroll scrollRectToVisible:[tab convertRect:tab.bounds toView:self.tabScroll] animated:NO];
    }
}

- (int)addGame:(NSString *)jarPath width:(int)width height:(int)height
           fps:(int)fpsLimit title:(NSString *)title {
    int slot = -1;
    for (int candidate = 0; candidate < JVM_BRIDGE_MAX_SLOTS; candidate++) {
        if (![self sessionForSlot:candidate]) {
            slot = candidate;
            break;
        }
    }
    if (slot < 0) {
        return -1;
    }

    RTGameSession *session = [[RTGameSession alloc] init];
    session.slot = slot;
    session.jarPath = jarPath;
    session.title = title.length ? title : jarPath.lastPathComponent;
    session.width = width > 0 ? width : g_width;
    session.height = height > 0 ? height : g_height;
    session.fpsLimit = fpsLimit;
    session.running = YES;
    [self.sessions addObject:session];
    [self focusSlot:slot];
    [self startSession:session];
    return slot;
}

- (void)startSession:(RTGameSession *)session {
    NSString *saveRoot = @(g_save_root);
    NSString *base = session.jarPath.lastPathComponent.stringByDeletingPathExtension;
    saveRoot = [saveRoot stringByAppendingPathComponent:base];
    [[NSFileManager defaultManager] createDirectoryAtPath:saveRoot
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSString *jar = session.jarPath;
    int slot = session.slot;
    int width = session.width;
    int height = session.height;
    int fpsLimit = session.fpsLimit;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        printf("[RT] slot %d initializing %s\n", slot, jar.UTF8String);
        fflush(stdout);
        if (jvm_bridge_init_slot(slot, g_res_root, saveRoot.UTF8String, jar.UTF8String,
                                 width, height, 1, fpsLimit) != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                session.running = NO;
                if (slot == self.focusedSlot) {
                    self.statusLabel.text = @"jvm_bridge_init_slot failed";
                    self.statusPill.hidden = NO;
                }
                [self rebuildTabs];
            });
            return;
        }
        printf("[RT] slot %d running\n", slot);
        fflush(stdout);
        jvm_bridge_run_midlet_slot(slot, jar.UTF8String);
        printf("[RT] slot %d midlet run returned\n", slot);
        fflush(stdout);
        jvm_bridge_destroy_slot(slot);
        dispatch_async(dispatch_get_main_queue(), ^{
            session.running = NO;
            if (slot == self.focusedSlot) {
                [self updateStatus];
            }
            [self rebuildTabs];
            if (self.sessions.count == 0) {
                j2me_render_stop();
                j2me_render_cleanup();
            }
        });
    });
}

- (void)focusSlot:(int)slot {
    RTGameSession *session = [self sessionForSlot:slot];
    if (!session) {
        return;
    }
    self.focusedSlot = slot;
    jvm_bridge_set_focused_slot(slot);
    j2me_input_set_canvas_size(session.width, session.height);
    self.gameView.canvasWidth = session.width;
    self.gameView.canvasHeight = session.height;
    self.gameView.currentImage = session.lastImage;
    [self updateStatus];
    rt_form_ui_present(j2me_ui_get_slot_active_action(slot));
    [self rebuildTabs];
}

- (void)selectTab:(UIButton *)sender {
    RTGameSession *session = [self sessionForSlot:(int) sender.tag];
    if (session) {
        [self focusSlot:session.slot];
    }
}

- (void)closeTab:(UIButton *)sender {
    RTGameSession *session = [self sessionForSlot:(int) sender.tag];
    if (session) {
        [self closeSlot:session.slot];
    }
}

- (void)closeSlot:(int)slot {
    RTGameSession *session = [self sessionForSlot:slot];
    if (!session) {
        return;
    }
    [self.sessions removeObject:session];
    jvm_bridge_request_stop_slot(slot);

    if (self.focusedSlot == slot) {
        self.focusedSlot = -1;
        RTGameSession *next = self.sessions.firstObject;
        if (next) {
            [self focusSlot:next.slot];
        } else {
            self.gameView.currentImage = NULL;
            [self updateStatus];
            [self rebuildTabs];
            if (self.navigationController) {
                [self.navigationController popViewControllerAnimated:YES];
            }
        }
    } else {
        [self rebuildTabs];
    }
}

- (void)closeGame:(UIButton *)sender {
    (void)sender;
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)scheduleSyntheticEvents {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, '5');
            });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (3.4 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, '5');
            });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (4.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                j2me_input_post_touch(J2ME_INPUT_POINTER_PRESSED, 40, 60);
            });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (4.3 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                j2me_input_post_touch(J2ME_INPUT_POINTER_DRAGGED, 60, 80);
            });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (4.6 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                j2me_input_post_touch(J2ME_INPUT_POINTER_RELEASED, 80, 100);
            });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBarHidden = YES;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBarHidden = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.midletStarted) return;
    self.midletStarted = YES;

    if (self.sessions.count == 0 && (self.jarPath.length || (g_midlet_jar && g_midlet_jar[0]))) {
        NSString *jar = self.jarPath.length ? self.jarPath : @(g_midlet_jar);
        [self addGame:jar
                width:self.canvasWidth > 0 ? self.canvasWidth : g_width
               height:self.canvasHeight > 0 ? self.canvasHeight : g_height
                  fps:self.fpsLimit > 0 ? self.fpsLimit : g_fps_limit
                title:nil];
    }

    if (getenv("RT_SYNTH_INPUT")) {
        [self scheduleSyntheticEvents];
    }

    const char *cycle = getenv("RT_FOCUS_CYCLE");
    if (cycle && cycle[0]) {
        double seconds = atof(cycle);
        if (seconds > 0.2) {
            [NSTimer scheduledTimerWithTimeInterval:seconds
                                             target:self
                                           selector:@selector(cycleFocus:)
                                           userInfo:nil
                                            repeats:YES];
        }
    }

    const char *closeAfter = getenv("RT_CLOSE_AFTER");
    if (closeAfter && closeAfter[0]) {
        double seconds = atof(closeAfter);
        if (seconds > 0.2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (seconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.sessions.count < 2) return;
                [self closeSlot:((RTGameSession *) self.sessions[0]).slot];
            });
        }
    }
}

- (void)cycleFocus:(NSTimer *)timer {
    (void)timer;
    if (self.sessions.count < 2) return;
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < self.sessions.count; i++) {
        if (((RTGameSession *) self.sessions[i]).slot == self.focusedSlot) {
            index = i;
            break;
        }
    }
    RTGameSession *next = self.sessions[(index + 1) % self.sessions.count];
    [self focusSlot:next.slot];
}

@end

// ------------------------------------------------------------- app delegate

static int g_shell_mode = 0;

@interface RTSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation RTSceneDelegate

- (void)scene:(UIScene *)scene
        willConnectToSession:(UISceneSession *)session
        options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    (void)connectionOptions;
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *) scene];
    UIViewController *root = nil;
    if (g_shell_mode) {
        root = (__bridge_transfer UIViewController *) rt_shell_root_controller();
    } else {
        RTViewController *controller = [[RTViewController alloc] init];
        g_controller = controller;
        root = controller;
    }
    window.rootViewController = root;
    [window makeKeyAndVisible];
    self.window = window;
}

@end

@interface RTAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation RTAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
        configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
        options:(UISceneConnectionOptions *)options {
    (void)application;
    (void)options;
    UISceneConfiguration *config =
            [[UISceneConfiguration alloc] initWithName:@"Default"
                                           sessionRole:connectingSceneSession.role];
    config.delegateClass = [RTSceneDelegate class];
    return config;
}

@end

// ------------------------------------------------------------ flush bridge

static int rt_snapshot_interval(void) {
    static int interval = 0;
    if (interval == 0) {
        const char *value = getenv("RT_SNAPSHOT_INTERVAL");
        interval = value ? atoi(value) : 60;
        if (interval <= 0) {
            interval = 60;
        }
    }
    return interval;
}

static void rt_write_snapshot(CGImageRef image) {
    const char *dir = getenv("RT_SNAPSHOT_DIR");
    if (!dir || !dir[0]) {
        return;
    }
    mkdir(dir, 0755);
    char path[1024];
    snprintf(path, sizeof(path), "%s/frame_%06d.png", dir, g_frames);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
            NULL, (const UInt8 *) path, (CFIndex) strlen(path), false);
    if (!url) {
        return;
    }
    CGImageDestinationRef destination =
            CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    if (destination) {
        CGImageDestinationAddImage(destination, image, NULL);
        CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CFRelease(url);
}

static void rt_on_slot_flush(int slot, void *image, int width, int height) {
    if (!image) return;
    CGImageRef cg = (CGImageRef) image;
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) {
        CGImageRelease(cg);
        return;
    }
    if (g_slot_started[slot] == 0) {
        g_slot_started[slot] = rt_now();
    }
    g_slot_frames[slot]++;
    if (g_slot_frames[slot] % 30 == 0) {
        double elapsed = rt_now() - g_slot_started[slot];
        double fps = elapsed > 0 ? (double) g_slot_frames[slot] / elapsed : 0;
        printf("[RT] slot %d frames=%d %.1fs fps=%.1f %dx%d\n",
               slot, g_slot_frames[slot], elapsed, fps, width, height);
        fflush(stdout);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        RTGameSession *session = [g_controller sessionForSlot:slot];
        if (!session) {
            CGImageRelease(cg);
            return;
        }
        session.lastImage = cg;
    });
}

static void rt_on_flush(void *image, int width, int height) {
    if (!image) return;
    CGImageRef cg = (CGImageRef) image;
    int slot = jvm_bridge_get_focused_slot();
    g_frames++;
    dispatch_async(dispatch_get_main_queue(), ^{
        RTViewController *controller = g_controller;
        if (!controller) {
            CGImageRelease(cg);
            return;
        }
        controller.gameView.canvasWidth = width;
        controller.gameView.canvasHeight = height;
        controller.gameView.currentImage = cg;
        [controller updateStatus];
        if (g_frames % rt_snapshot_interval() == 0) {
            rt_write_snapshot(cg);
        }
        CGImageRelease(cg);
    });
}

static UINavigationController *rt_active_navigation_controller(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindow *window = ((UIWindowScene *) scene).keyWindow;
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:[UINavigationController class]]) {
            return (UINavigationController *) root;
        }
        if (root.navigationController) {
            return root.navigationController;
        }
    }
    return nil;
}

void *rt_create_game_controller(const char *jar_path, int width, int height,
                                int fps_limit) {
    RTViewController *controller = [[RTViewController alloc] init];
    controller.jarPath = jar_path ? @(jar_path) : nil;
    controller.canvasWidth = width;
    controller.canvasHeight = height;
    controller.fpsLimit = fps_limit;
    controller.showsBackButton = YES;
    g_controller = controller;
    return (__bridge_retained void *) controller;
}

void *rt_host_controller(void) {
    if (!g_controller) {
        RTViewController *controller = [[RTViewController alloc] init];
        controller.showsBackButton = YES;
        g_controller = controller;
    }
    return (__bridge void *) g_controller;
}

int rt_host_running_count(void) {
    return (int) g_controller.sessions.count;
}

void rt_present_game(const char *jar_path, int width, int height, int fps_limit,
                     const char *title) {
    if (!jar_path || !jar_path[0]) return;
    NSString *jar = @(jar_path);
    NSString *name = (title && title[0]) ? @(title) : jar.lastPathComponent;
    dispatch_async(dispatch_get_main_queue(), ^{
        RTViewController *host = g_controller;
        if (!host) {
            host = [[RTViewController alloc] init];
            host.showsBackButton = YES;
            g_controller = host;
        }
        [host addGame:jar width:width height:height fps:fps_limit title:name];
        UINavigationController *nav = rt_active_navigation_controller();
        if (nav && ![nav.viewControllers containsObject:host]) {
            [nav pushViewController:host animated:YES];
        }
    });
}

int rt_run_ui(int argc, char **argv, const char *res_root, const char *save_root,
              const char *midlet_jar, int width, int height, int fps_limit) {
    g_res_root = res_root;
    g_save_root = save_root;
    g_midlet_jar = midlet_jar;
    g_width = width;
    g_height = height;
    g_fps_limit = fps_limit;
    g_shell_mode = (midlet_jar == NULL || midlet_jar[0] == '\0');
    g_started = rt_now();

    j2me_render_set_flush_callback(rt_on_flush);
    j2me_render_set_slot_flush_callback(rt_on_slot_flush);

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([RTAppDelegate class]));
    }
}
