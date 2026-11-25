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
#include "rt_form_panel.h"
#include "rt_background.h"
#include "rt_keys.h"
#include "rt_proxy_store.h"
#include "rt_library_vc.h"
#include "rt_theme.h"
#include "rt_host.h"
#include "rt_game_view.h"
#include "rt_tab_grid.h"

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

@interface RTGameSession : NSObject
@property(nonatomic) int slot;
@property(nonatomic, copy) NSString *jarPath;
@property(nonatomic, copy) NSString *title;
// Directory name (inside the save root) this tab writes RMS data to. Two tabs
// of the same JAR must never share it.
@property(nonatomic, copy) NSString *saveDir;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) int fpsLimit;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL fullKeyboard;
@property(nonatomic) BOOL turbo;
@property(nonatomic, copy) NSArray<NSNumber *> *keyCodes;
// Saved proxy id this tab connects through; empty means a direct connection.
@property(nonatomic, copy) NSString *proxyId;
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
@property(nonatomic, strong) UIButton *tabsButton;
@property(nonatomic, strong) UIButton *keyboardButton;
@property(nonatomic, strong) UIButton *aboutButton;
@property(nonatomic, strong) UIButton *proxyButton;
@property(nonatomic, strong) UITextField *keyboardField;
@property(nonatomic, strong) UIView *keypadContainer;
@property(nonatomic, strong) RTKeypadView *keypad;
@property(nonatomic, strong) NSLayoutConstraint *keypadHeight;

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

    self.keyboardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.keyboardButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyboardButton.tintColor = rt_color_text_secondary();
    self.keyboardButton.accessibilityLabel = @"Bàn phím iOS";
    [self.keyboardButton setImage:[[UIImage systemImageNamed:@"keyboard"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                         forState:UIControlStateNormal];
    [self.keyboardButton addTarget:self
                            action:@selector(toggleSystemKeyboard:)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.keyboardButton];

    // J2ME games cannot use the App Store review flow, so the credit lives in
    // the game chrome where it is always reachable.
    self.aboutButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.aboutButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.aboutButton.tintColor = rt_color_text_secondary();
    self.aboutButton.accessibilityLabel = @"Giới thiệu";
    [self.aboutButton setImage:[[UIImage systemImageNamed:@"exclamationmark.circle"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                      forState:UIControlStateNormal];
    [self.aboutButton addTarget:self
                         action:@selector(showAbout:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.aboutButton];

    // The proxy button sits next to About, as the last per-tab setting.
    self.proxyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.proxyButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.proxyButton.tintColor = rt_color_text_secondary();
    self.proxyButton.accessibilityLabel = @"Proxy của tab này";
    [self.proxyButton setImage:[[UIImage systemImageNamed:@"network"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                      forState:UIControlStateNormal];
    [self.proxyButton addTarget:self
                         action:@selector(showProxyPicker:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.proxyButton];

    // Off-screen responder that owns the system keyboard; it never shows text
    // itself, it only forwards keystrokes to the MIDlet.
    self.keyboardField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    self.keyboardField.delegate = self;
    self.keyboardField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyboardField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyboardField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.keyboardField.textColor = [UIColor clearColor];
    self.keyboardField.tintColor = [UIColor clearColor];
    self.keyboardField.backgroundColor = [UIColor clearColor];
    self.keyboardField.alpha = 0.02;
    // UIKit stops reporting deletes once the field is empty, which also stops
    // the key-repeat while the finger is held down. Parking invisible filler
    // in the field keeps the delete key a normal editing key: one tap sends one
    // event, holding the key repeats it, and the delegate refuses every change
    // so the filler never actually shrinks.
    self.keyboardField.text = [@"" stringByPaddingToLength:64 withString:@" " startingAtIndex:0];
    [self.view addSubview:self.keyboardField];

    self.tabsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.tabsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabsButton.tintColor = rt_color_text_secondary();
    self.tabsButton.accessibilityLabel = @"Cửa sổ đang chạy";
    [self.tabsButton addTarget:self
                        action:@selector(showTabs:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.tabsButton];

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

        [self.aboutButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-4],
        [self.aboutButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.aboutButton.widthAnchor constraintEqualToConstant:40],
        [self.aboutButton.heightAnchor constraintEqualToConstant:40],

        [self.proxyButton.trailingAnchor constraintEqualToAnchor:self.aboutButton.leadingAnchor constant:-2],
        [self.proxyButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.proxyButton.widthAnchor constraintEqualToConstant:40],
        [self.proxyButton.heightAnchor constraintEqualToConstant:40],

        [self.fpsButton.trailingAnchor constraintEqualToAnchor:self.proxyButton.leadingAnchor constant:-2],
        [self.fpsButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.fpsButton.widthAnchor constraintEqualToConstant:44],
        [self.fpsButton.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:4],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.keyboardButton.trailingAnchor constraintEqualToAnchor:self.fpsButton.leadingAnchor constant:-2],
        [self.keyboardButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.keyboardButton.widthAnchor constraintEqualToConstant:40],
        [self.keyboardButton.heightAnchor constraintEqualToConstant:40],

        [self.tabsButton.trailingAnchor constraintEqualToAnchor:self.keyboardButton.leadingAnchor constant:-2],
        [self.tabsButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.tabsButton.heightAnchor constraintEqualToConstant:36],

        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.tabsButton.leadingAnchor
                                                                 constant:-8],

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

        [self.keypad.topAnchor constraintEqualToAnchor:self.keypadContainer.topAnchor],
        [self.keypad.leadingAnchor constraintEqualToAnchor:self.keypadContainer.leadingAnchor],
        [self.keypad.trailingAnchor constraintEqualToAnchor:self.keypadContainer.trailingAnchor],
        [self.keypad.bottomAnchor constraintEqualToAnchor:self.keypadContainer.bottomAnchor],
    ]];

    self.keypadHeight = [self.keypadContainer.heightAnchor constraintEqualToConstant:190];
    self.keypadHeight.active = YES;

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

// The system QWERTY keyboard types straight into the focused MIDlet: every
// committed character is posted as a MIDP key press/release pair, matching
// what a handset reports for a printable key. J2ME has no clipboard or text
// input event on Canvas, so this is the only way to enter names in games that
// draw their own text fields.
- (void)toggleSystemKeyboard:(id)sender {
    (void)sender;
    if (self.keyboardField.isFirstResponder) {
        [self.keyboardField resignFirstResponder];
    } else {
        [self.keyboardField becomeFirstResponder];
    }
}

- (void)postKeyCharacters:(NSString *)text {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar ch = [text characterAtIndex:i];
        if (ch == '\n' || ch == '\r') {
            j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, -5);
            j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, -5);
            continue;
        }
        j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, (int) ch);
        j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, (int) ch);
    }
}

- (BOOL)textField:(UITextField *)textField
        shouldChangeCharactersInRange:(NSRange)range
                    replacementString:(NSString *)string {
    if (string.length == 0) {
        // Games that draw their own text fields erase with the right soft key,
        // not MIDP KEY_CLEAR.
        j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, -7);
        j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, -7);
    } else {
        [self postKeyCharacters:string];
    }
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self postKeyCharacters:@"\n"];
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.keyboardButton.tintColor = rt_color_accent();
    if (textField.text.length == 0) {
        textField.text = [@"" stringByPaddingToLength:64 withString:@" " startingAtIndex:0];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.keyboardButton.tintColor = rt_color_text_secondary();
}

- (void)rebuildTabs {
    RTGameSession *focused = [self sessionForSlot:self.focusedSlot];
    self.titleLabel.text = focused ? focused.title : @"";

    BOOL showBar = self.sessions.count > 1 || self.showsBackButton;
    BOOL showTabs = self.sessions.count > 1;
    self.topBar.hidden = !showBar;
    self.topBarHeight.constant = showBar ? 44 : 0;

    self.tabsButton.hidden = !showTabs;
    if (showTabs) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"square.on.square"];
        config.title = [NSString stringWithFormat:@"%lu", (unsigned long) self.sessions.count];
        config.imagePadding = 4;
        config.baseForegroundColor = rt_color_text_secondary();
        config.contentInsets = NSDirectionalEdgeInsetsMake(6, 8, 6, 8);
        self.tabsButton.configuration = config;
        self.tabsButton.accessibilityValue = [NSString stringWithFormat:@"%lu cửa sổ",
                                                                        (unsigned long) self.sessions.count];
    }
    [self.view setNeedsLayout];
}

- (void)showTabs:(id)sender {
    (void)sender;
    if (self.sessions.count == 0) return;

    printf("[RT] showing tab grid (%lu sessions)\n", (unsigned long) self.sessions.count);
    fflush(stdout);
    RTTabGridController *grid = [[RTTabGridController alloc] init];
    __weak RTViewController *weakSelf = self;
    grid.itemsProvider = ^NSArray<RTTabGridItem *> *{
        RTViewController *strongSelf = weakSelf;
        if (!strongSelf) return @[];
        NSMutableArray<RTTabGridItem *> *items = [NSMutableArray array];
        for (RTGameSession *session in strongSelf.sessions) {
            RTTabGridItem *item = [[RTTabGridItem alloc] init];
            item.slot = session.slot;
            item.title = session.title;
            item.running = session.running;
            item.focused = session.slot == strongSelf.focusedSlot;
            [items addObject:item];
        }
        return items;
    };
    grid.imageProvider = ^UIImage *(int slot) {
        RTGameSession *session = [weakSelf sessionForSlot:slot];
        if (!session || !session.lastImage) return nil;
        return [UIImage imageWithCGImage:session.lastImage];
    };
    grid.onSelect = ^(int slot) {
        RTViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf focusSlot:slot];
        [strongSelf dismissViewControllerAnimated:YES completion:nil];
    };
    grid.onClose = ^(int slot) {
        RTViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf closeSlot:slot];
        if (strongSelf.sessions.count == 0) {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        } else {
            [grid reload];
        }
    };
    [grid reload];
    [self presentViewController:grid animated:YES completion:nil];
}

// A single IP can hold only a couple of accounts, so a new tab must not inherit
// a proxy another running tab already uses: take the requested one when it is
// free, otherwise the first saved proxy nobody holds, otherwise go direct.
- (NSString *)proxyIdForNewSession:(NSString *)requested {
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (RTGameSession *session in self.sessions) {
        if (session.proxyId.length > 0) {
            [used addObject:session.proxyId];
        }
    }
    if (requested.length > 0 && ![used containsObject:requested]) {
        return requested;
    }
    for (NSDictionary *proxy in rt_proxies()) {
        NSString *identifier = proxy[@"id"];
        if (identifier.length > 0 && ![used containsObject:identifier]) {
            return identifier;
        }
    }
    return @"";
}

- (int)addGame:(NSString *)jarPath width:(int)width height:(int)height
           fps:(int)fpsLimit title:(NSString *)title
  fullKeyboard:(BOOL)fullKeyboard turbo:(BOOL)turbo
      keyCodes:(NSArray<NSNumber *> *)keyCodes
       proxyId:(NSString *)proxyId {
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
    session.fullKeyboard = fullKeyboard;
    session.turbo = turbo;
    session.keyCodes = keyCodes;
    session.proxyId = [self proxyIdForNewSession:proxyId ?: @""];
    session.running = YES;
    [self.sessions addObject:session];
    [self focusSlot:slot];
    [self startSession:session];
    return slot;
}

- (void)applySessionControls:(RTGameSession *)session {
    // The pad layout and turbo switch are shared by every tab, so they follow
    // the focused session instead of being duplicated per game.
    self.keypad.fullKeyboard = session ? session.fullKeyboard : NO;
    self.keypad.turboEnabled = session ? session.turbo : NO;
    self.keypad.keyCodes = session.keyCodes;
    self.keypadHeight.constant = self.keypad.preferredHeight;
    self.proxyButton.tintColor = session.proxyId.length > 0
            ? rt_color_accent()
            : rt_color_text_secondary();
    self.proxyButton.accessibilityValue = session.proxyId.length > 0 ? @"đang dùng proxy" : @"trực tiếp";
    printf("[RT] keypad full=%d turbo=%d keys=%lu proxy=%s\n", self.keypad.fullKeyboard,
           self.keypad.turboEnabled, (unsigned long) self.keypad.keyCodes.count,
           session.proxyId.length > 0 ? session.proxyId.UTF8String : "-");
    fflush(stdout);
}

// RMS belongs to a tab, not to a JAR: launching the same game twice gives each
// session its own directory so two accounts do not overwrite each other's
// RecordStores. The first tab keeps the plain name, later ones take the first
// free "<name> N".
- (NSString *)claimSaveDirectoryForSession:(RTGameSession *)session {
    NSString *base = session.jarPath.lastPathComponent.stringByDeletingPathExtension;
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (RTGameSession *other in self.sessions) {
        if (other != session && other.saveDir.length > 0) {
            [used addObject:other.saveDir];
        }
    }
    NSString *name = base;
    for (int n = 2; [used containsObject:name]; n++) {
        name = [NSString stringWithFormat:@"%@ %d", base, n];
    }
    session.saveDir = name;
    NSString *directory = [@(g_save_root) stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

- (void)startSession:(RTGameSession *)session {
    NSString *saveRoot = [self claimSaveDirectoryForSession:session];
    printf("[RT] slot %d save=%s\n", session.slot, saveRoot.lastPathComponent.UTF8String);
    fflush(stdout);

    NSString *jar = session.jarPath;
    int slot = session.slot;
    int width = session.width;
    int height = session.height;
    int fpsLimit = session.fpsLimit;

    NSDictionary *proxy = rt_proxy_with_id(session.proxyId);
    NSString *proxyHost = proxy[@"host"] ?: @"";
    int proxyPort = [proxy[@"port"] intValue];
    NSString *proxyUser = proxy[@"user"] ?: @"";
    NSString *proxyPass = proxy[@"pass"] ?: @"";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Before the JVM exists: the bridge keeps the choice and applies it
        // once init succeeds, so the first socket already tunnels.
        jvm_bridge_set_slot_proxy(slot, proxyHost.UTF8String, proxyPort,
                                  proxyUser.UTF8String, proxyPass.UTF8String);
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
    [self applySessionControls:session];
    [self updateStatus];
    rt_form_ui_present(j2me_ui_get_slot_active_action(slot));
    [self rebuildTabs];
}

- (void)showProxyPicker:(id)sender {
    UIButton *senderButton = (UIButton *) sender;
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:@"Proxy cho tab này"
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    RTGameSession *session = [self sessionForSlot:self.focusedSlot];
    NSString *current = session.proxyId ?: @"";

    NSString *directTitle = current.length == 0 ? @"✓  Không dùng proxy" : @"Không dùng proxy";
    UIAlertAction *direct = [UIAlertAction actionWithTitle:directTitle
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction *action) {
        [self applyProxyId:@"" forSession:session];
    }];
    [sheet addAction:direct];

    for (NSDictionary *proxy in rt_proxies()) {
        NSString *identifier = proxy[@"id"];
        BOOL selected = [identifier isEqualToString:current];
        NSString *title = [NSString stringWithFormat:@"%@%@  ·  %@",
                                                     selected ? @"✓  " : @"",
                                                     rt_proxy_label(proxy),
                                                     rt_proxy_detail(proxy)];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *chosen) {
            [self applyProxyId:identifier forSession:session];
        }];
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = senderButton;
    sheet.popoverPresentationController.sourceRect = senderButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)applyProxyId:(NSString *)proxyId forSession:(RTGameSession *)session {
    if (!session) return;
    session.proxyId = proxyId ?: @"";
    NSDictionary *proxy = rt_proxy_with_id(session.proxyId);
    jvm_bridge_set_slot_proxy(session.slot,
                              proxy ? [proxy[@"host"] UTF8String] : "",
                              proxy ? [proxy[@"port"] intValue] : 0,
                              proxy ? [proxy[@"user"] UTF8String] : "",
                              proxy ? [proxy[@"pass"] UTF8String] : "");
    rt_set_game_proxy(session.jarPath.lastPathComponent, session.proxyId);
    if (session.slot == self.focusedSlot) {
        [self applySessionControls:session];
    }
}

- (void)showAbout:(id)sender {
    (void) sender;
    NSString *message = @"Ứng dụng: JL-Next\n"
                        @"Người làm: Trần Đức Huy\n\n"
                        @"Thành phần bên thứ ba:\n"
                        @"• J2ME Loader\n"
                        @"• miniJVM";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Giới thiệu"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// The library shows one aggregate row for running games; deleting it means
// closing every tab. The run threads still own jvm_bridge_destroy_slot, so
// this only drops the sessions and asks each slot to stop.
- (void)closeAllSessions {
    NSArray<RTGameSession *> *all = [self.sessions copy];
    if (all.count == 0) {
        return;
    }
    [self.sessions removeAllObjects];
    for (RTGameSession *session in all) {
        jvm_bridge_request_stop_slot(session.slot);
    }
    self.focusedSlot = -1;
    self.gameView.currentImage = NULL;
    [self updateStatus];
    [self rebuildTabs];
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
        int kb = getenv("RT_FULL_KEYBOARD") ? 1 : 0;
        int turbo = getenv("RT_TURBO") ? 1 : 0;
        NSString *keysEnv = getenv("RT_KEYS") ? @(getenv("RT_KEYS")) : nil;
        [self addGame:jar
                width:self.canvasWidth > 0 ? self.canvasWidth : g_width
               height:self.canvasHeight > 0 ? self.canvasHeight : g_height
                  fps:self.fpsLimit > 0 ? self.fpsLimit : g_fps_limit
                title:nil
         fullKeyboard:kb
                turbo:turbo
             keyCodes:keysEnv.length ? rt_key_codes_from_string(keysEnv) : nil
              proxyId:getenv("RT_PROXY") ? @(getenv("RT_PROXY")) : @""];
    }

    if (getenv("RT_SYSTEM_KEYBOARD")) {
        [self.keyboardField becomeFirstResponder];
    }
    if (getenv("RT_TYPE_TEXT")) {
        NSString *text = [NSString stringWithUTF8String:getenv("RT_TYPE_TEXT")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self postKeyCharacters:text]; });
    }

    if (getenv("RT_CLOSE_FOCUSED")) {
        double delay = atof(getenv("RT_CLOSE_FOCUSED"));
        if (delay > 0.2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               RTGameSession *focused = [self sessionForSlot:self.focusedSlot];
                               if (focused) {
                                   [self closeSlot:focused.slot];
                               }
                           });
        }
    }

    if (getenv("RT_SHOW_ABOUT")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [self showAbout:nil];
                       });
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

    // Headless verification hook: open the window switcher once two games run.
    const char *showGrid = getenv("RT_SHOW_TAB_GRID");
    if (showGrid && showGrid[0]) {
        double seconds = atof(showGrid);
        if (seconds > 0.2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (seconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.sessions.count >= 2 && !self.presentedViewController) {
                    [self showTabs:nil];
                }
            });
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

static void rt_handle_open_urls(NSSet<UIOpenURLContext *> *contexts, UIWindow *window) {
    if (contexts.count == 0) {
        return;
    }
    BOOL imported = NO;
    for (UIOpenURLContext *context in contexts) {
        NSURL *url = context.URL;
        if (!url.isFileURL) {
            continue;
        }
        if (rt_import_jar_path(url.path.UTF8String)) {
            imported = YES;
        }
    }
    if (imported && [window.rootViewController isKindOfClass:[UINavigationController class]]) {
        [(UINavigationController *) window.rootViewController popToRootViewControllerAnimated:YES];
    }
}

@implementation RTSceneDelegate

- (void)scene:(UIScene *)scene
        openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    rt_handle_open_urls(URLContexts, self.window);
}

- (void)scene:(UIScene *)scene
        willConnectToSession:(UISceneSession *)session
        options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
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
    // A JAR opened from Files before the scene existed arrives here, not in
    // scene:openURLContexts:.
    rt_handle_open_urls(connectionOptions.URLContexts, window);
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

void rt_host_close_all(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RTViewController *host = g_controller;
        if (host) {
            [host closeAllSessions];
        }
    });
}

int rt_host_running_count(void) {
    return (int) g_controller.sessions.count;
}

void rt_present_game(const char *jar_path, int width, int height, int fps_limit,
                     const char *title, int full_keyboard, int turbo,
                     const char *keys, const char *proxy_id) {
    if (!jar_path || !jar_path[0]) return;
    NSString *jar = @(jar_path);
    NSString *name = (title && title[0]) ? @(title) : jar.lastPathComponent;
    NSArray<NSNumber *> *keyCodes = keys && keys[0]
            ? rt_key_codes_from_string(@(keys))
            : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        RTViewController *host = g_controller;
        if (!host) {
            host = [[RTViewController alloc] init];
            host.showsBackButton = YES;
            g_controller = host;
        }
        NSString *chosenProxy = proxy_id && proxy_id[0] ? @(proxy_id) : @"";
        if (chosenProxy.length == 0 && getenv("RT_PROXY")) {
            chosenProxy = @(getenv("RT_PROXY"));
        }
        [host addGame:jar width:width height:height fps:fps_limit title:name
      fullKeyboard:full_keyboard turbo:turbo keyCodes:keyCodes
           proxyId:chosenProxy];
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
    rt_background_install();

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([RTAppDelegate class]));
    }
}
