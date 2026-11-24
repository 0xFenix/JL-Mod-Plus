// UIKit host for the J2ME runtime: presents the frames delivered by the
// j2me_render flush callback and turns on-screen controls into MIDP key or
// pointer events. Rendering and input stay in the vendored runtime; this file
// only supplies the window that a person actually looks at and touches.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include <stdio.h>
#include <string.h>
#include <time.h>

#include "jvm_bridge.h"
#include "j2me_render.h"
#include "j2me_input.h"
#include "j2me_ui.h"
#include "host_form.h"
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
    RT_KEY_DOWN, '1', '2',
    '3', '4', '5',
    '6', '7', '8',
    '9', '*', '0',
};
static NSString *const rt_keypad_labels[] = {
    @"LSK", @"▲", @"RSK",
    @"◀", @"OK", @"▶",
    @"▼", @"1", @"2",
    @"3", @"4", @"5",
    @"6", @"7", @"8",
    @"9", @"*", @"0",
    @"#", @"", @"",
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

/// Maps a touch inside the aspect-fitted image area onto canvas coordinates.
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
@end

@implementation RTKeyButton
@end

@interface RTKeypadView : UIView
@property(nonatomic, strong) NSMutableArray<RTKeyButton *> *buttons;
@end

@implementation RTKeypadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    // Grid of equal cells so the pad keeps working at any screen width.
    UIStackView *column = [[UIStackView alloc] initWithFrame:self.bounds];
    column.axis = UILayoutConstraintAxisVertical;
    column.distribution = UIStackViewDistributionFillEqually;
    column.spacing = 4;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [column.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
    ]];

    self.buttons = [NSMutableArray array];
    for (int row = 0; row * rt_keypad_cols < (int) (sizeof(rt_keypad_keys) / sizeof(rt_keypad_keys[0])); row++) {
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        line.spacing = 4;

        for (int col = 0; col < rt_keypad_cols; col++) {
            int index = row * rt_keypad_cols + col;
            NSString *label = rt_keypad_labels[index];
            if ([label length] == 0) {
                UIView *spacer = [[UIView alloc] init];
                [line addArrangedSubview:spacer];
                continue;
            }
            RTKeyButton *button = [RTKeyButton buttonWithType:UIButtonTypeSystem];
            button.midpKeyCode = rt_keypad_keys[index];
            [button setTitle:label forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium];
            button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
            button.layer.cornerRadius = 6;
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
    j2me_input_post_key(J2ME_INPUT_KEY_PRESSED, button.midpKeyCode);
}

- (void)keyUp:(RTKeyButton *)button {
    j2me_input_post_key(J2ME_INPUT_KEY_RELEASED, button.midpKeyCode);
}

@end

// ------------------------------------------------------------- view control

@interface RTViewController : UIViewController
@property(nonatomic, strong) RTGameView *gameView;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic) BOOL midletStarted;
@end

@implementation RTViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.gameView = [[RTGameView alloc] init];
    self.gameView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gameView.canvasWidth = g_width;
    self.gameView.canvasHeight = g_height;
    [self.view addSubview:self.gameView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.text = @"starting…";
    [self.view addSubview:self.statusLabel];

    RTKeypadView *keypad = [[RTKeypadView alloc] init];
    keypad.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:keypad];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.gameView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.gameView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.gameView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.gameView.bottomAnchor constant:2],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [keypad.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [keypad.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [keypad.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [keypad.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [keypad.heightAnchor constraintEqualToConstant:230],
    ]];

    rt_form_ui_attach((__bridge void *) self.view);
    rt_form_ui_present(j2me_ui_get_slot_active_action(0));
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.midletStarted) return;
    self.midletStarted = YES;

    // The MIDlet runs on its own thread; the event loop inside the runtime
    // blocks until the game exits.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        printf("[RT] initializing slot\n");
        fflush(stdout);
        if (jvm_bridge_init_slot(0, g_res_root, g_save_root, g_midlet_jar,
                                 g_width, g_height, 1, g_fps_limit) != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"jvm_bridge_init_slot failed";
            });
            return;
        }
        jvm_bridge_set_focused_slot(0);
        j2me_input_set_canvas_size(g_width, g_height);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"running";
        });
        jvm_bridge_run_midlet_slot(0, g_midlet_jar);
        printf("[RT] midlet run returned, frames=%d\n", g_frames);
        fflush(stdout);
        j2me_render_stop();
        j2me_render_cleanup();
        jvm_bridge_destroy_slot(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"MIDlet finished";
        });
    });

    // Synthetic events for automated input verification: prove the ring buffer,
    // the runner's dispatch, and the Canvas callbacks agree. Real touches still
    // arrive through RTGameView's aspect-fit mapping.
    if (getenv("RT_SYNTH_INPUT")) {
        [self scheduleSyntheticEvents];
    }
}

@end

// ------------------------------------------------------------- app delegate

// The scene-based life cycle is mandatory for apps built with current SDKs;
// a legacy UIWindow in the app delegate is rejected at launch.
static RTViewController *g_controller = nil;

@interface RTSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation RTSceneDelegate

- (void)scene:(UIScene *)scene
        willConnectToSession:(UISceneSession *)session
        options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *) scene];
    RTViewController *controller = [[RTViewController alloc] init];
    window.rootViewController = controller;
    [window makeKeyAndVisible];
    g_controller = controller;
    self.window = window;
}

@end

@interface RTAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation RTAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
        configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
        options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config =
            [[UISceneConfiguration alloc] initWithName:@"Default"
                                           sessionRole:connectingSceneSession.role];
    config.delegateClass = [RTSceneDelegate class];
    return config;
}

@end

// ------------------------------------------------------------ flush bridge

static void rt_on_flush(void *image, int width, int height) {
    if (!image) return;
    CGImageRef cg = (CGImageRef) image;
    g_frames++;
    if (g_frames % 30 == 0) {
        double elapsed = rt_now() - g_started;
        double fps = elapsed > 0 ? (double) g_frames / elapsed : 0;
        printf("[RT] frames=%d %.1fs fps=%.1f %dx%d\n", g_frames, elapsed, fps, width, height);
        fflush(stdout);
        NSString *status = [NSString stringWithFormat:@"%dx%d  %.1f fps", width, height, fps];
        dispatch_async(dispatch_get_main_queue(), ^{
            g_controller.statusLabel.text = status;
        });
    }
    // The layer retains the image, so the callback's reference is ours to drop.
    dispatch_async(dispatch_get_main_queue(), ^{
        RTViewController *controller = g_controller;
        if (!controller) {
            CGImageRelease(cg);
            return;
        }
        controller.gameView.canvasWidth = width;
        controller.gameView.canvasHeight = height;
        controller.gameView.currentImage = cg;
        CGImageRelease(cg);
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
    g_started = rt_now();

    j2me_render_set_flush_callback(rt_on_flush);

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([RTAppDelegate class]));
    }
}
