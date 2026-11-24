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
static NSString *const rt_keypad_labels[] = {
    @"LSK", @"▲", @"RSK",
    @"◀", @"OK", @"▶",
    @"*", @"▼", @"#",
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
        // Keep pixel art crisp: Core Animation smooths scaled layer contents by
        // default, which blurs a 240x320 framebuffer up to the screen size.
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

// ------------------------------------------------------------ game sessions

// One running MIDlet. A slot is the engine's tab index: every slot owns a JVM,
// a save directory and a render context, and only the focused slot receives
// input, so switching tabs changes focus instead of restarting the game.
@interface RTGameSession : NSObject
@property(nonatomic) int slot;
@property(nonatomic, copy) NSString *jarPath;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) int fpsLimit;
@property(nonatomic) BOOL running;
/// Latest frame for this slot; the setter takes ownership of one reference.
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
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIView *topBar;
@property(nonatomic, strong) NSLayoutConstraint *topBarHeight;
@property(nonatomic, strong) UIButton *libraryButton;
@property(nonatomic, strong) UIScrollView *tabScroll;
@property(nonatomic, strong) UIStackView *tabStack;
@property(nonatomic, strong) NSMutableArray<RTGameSession *> *sessions;
@property(nonatomic) int focusedSlot;
@property(nonatomic) BOOL midletStarted;
// Set by the library before presentation; globals stay as the script-driven
// defaults so automated runs keep working unchanged.
@property(nonatomic, copy) NSString *jarPath;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@property(nonatomic) int fpsLimit;
@property(nonatomic) BOOL showsBackButton;
@end

static RTViewController *g_controller = nil;

@implementation RTViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableArray array];
        _focusedSlot = -1;
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
    self.view.backgroundColor = [UIColor blackColor];

    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBar.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.topBar.clipsToBounds = YES;
    [self.view addSubview:self.topBar];

    self.libraryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.libraryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.libraryButton setTitle:@"‹ Thư viện" forState:UIControlStateNormal];
    self.libraryButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.libraryButton addTarget:self
                           action:@selector(closeGame:)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.libraryButton];

    self.tabScroll = [[UIScrollView alloc] init];
    self.tabScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabScroll.showsHorizontalScrollIndicator = NO;
    [self.topBar addSubview:self.tabScroll];

    self.tabStack = [[UIStackView alloc] init];
    self.tabStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabStack.axis = UILayoutConstraintAxisHorizontal;
    self.tabStack.spacing = 6;
    [self.tabScroll addSubview:self.tabStack];

    self.gameView = [[RTGameView alloc] init];
    self.gameView.translatesAutoresizingMaskIntoConstraints = NO;
    int width = self.canvasWidth > 0 ? self.canvasWidth : g_width;
    int height = self.canvasHeight > 0 ? self.canvasHeight : g_height;
    self.gameView.canvasWidth = width;
    self.gameView.canvasHeight = height;
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
    self.topBarHeight = [self.topBar.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        self.topBarHeight,

        [self.libraryButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:6],
        [self.libraryButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.libraryButton.widthAnchor constraintLessThanOrEqualToConstant:100],

        [self.tabScroll.leadingAnchor constraintEqualToAnchor:self.libraryButton.trailingAnchor constant:6],
        [self.tabScroll.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-6],
        [self.tabScroll.topAnchor constraintEqualToAnchor:self.topBar.topAnchor constant:3],
        [self.tabScroll.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:-3],

        [self.tabStack.leadingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.leadingAnchor],
        [self.tabStack.trailingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.trailingAnchor],
        [self.tabStack.topAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.topAnchor],
        [self.tabStack.bottomAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.bottomAnchor],
        [self.tabStack.heightAnchor constraintEqualToAnchor:self.tabScroll.frameLayoutGuide.heightAnchor],

        [self.gameView.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.gameView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.gameView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.gameView.bottomAnchor constant:2],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [keypad.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [keypad.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [keypad.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [keypad.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [keypad.heightAnchor constraintEqualToConstant:150],
    ]];

    rt_form_ui_attach((__bridge void *) self.view);
    rt_form_ui_present(j2me_ui_get_slot_active_action(self.focusedSlot >= 0 ? self.focusedSlot : 0));
    [self rebuildTabs];
}

/// Tab strip: one entry per running game with a close control, plus the way
/// back to the library. Hidden while a single game runs full screen.
- (void)rebuildTabs {
    for (UIView *view in self.tabStack.arrangedSubviews) {
        [self.tabStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (RTGameSession *session in self.sessions) {
        UIView *tab = [[UIView alloc] init];
        tab.backgroundColor = session.slot == self.focusedSlot
                ? [UIColor colorWithWhite:1.0 alpha:0.18]
                : [UIColor colorWithWhite:1.0 alpha:0.06];
        tab.layer.cornerRadius = 6;

        UIButton *title = [UIButton buttonWithType:UIButtonTypeSystem];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [title setTitle:session.running ? session.title : [session.title stringByAppendingString:@" (x)"]
               forState:UIControlStateNormal];
        title.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        title.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 4);
        title.tag = session.slot;
        [title addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
        [tab addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        close.tag = session.slot;
        [close addTarget:self action:@selector(closeTab:) forControlEvents:UIControlEventTouchUpInside];
        [tab addSubview:close];

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:tab.leadingAnchor],
            [title.topAnchor constraintEqualToAnchor:tab.topAnchor],
            [title.bottomAnchor constraintEqualToAnchor:tab.bottomAnchor],
            [close.leadingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [close.trailingAnchor constraintEqualToAnchor:tab.trailingAnchor constant:-4],
            [close.centerYAnchor constraintEqualToAnchor:tab.centerYAnchor],
        ]];
        [self.tabStack addArrangedSubview:tab];
    }
    BOOL showBar = self.sessions.count > 1 || self.showsBackButton;
    self.topBar.hidden = !showBar;
    self.topBarHeight.constant = showBar ? 36 : 0;
    [self.view layoutIfNeeded];
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
    // Each game keeps its own save directory so record stores and config do
    // not bleed between titles.
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

    // The MIDlet runs on its own thread; the event loop inside the runtime
    // blocks until that game exits.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        printf("[RT] slot %d initializing %s\n", slot, jar.UTF8String);
        fflush(stdout);
        if (jvm_bridge_init_slot(slot, g_res_root, saveRoot.UTF8String, jar.UTF8String,
                                 width, height, 1, fpsLimit) != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                session.running = NO;
                if (slot == self.focusedSlot) {
                    self.statusLabel.text = @"jvm_bridge_init_slot failed";
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
                self.statusLabel.text = @"MIDlet finished";
            }
            [self rebuildTabs];
            // Render contexts are process wide, so they may only be torn down
            // once no slot is left to draw into them.
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
    self.statusLabel.text = session.running ? @"running" : @"MIDlet finished";
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
    // The run thread owns teardown: it returns from the game loop, destroys the
    // slot and then reports completion.
    jvm_bridge_request_stop_slot(slot);

    if (self.focusedSlot == slot) {
        self.focusedSlot = -1;
        RTGameSession *next = self.sessions.firstObject;
        if (next) {
            [self focusSlot:next.slot];
        } else {
            self.gameView.currentImage = NULL;
            self.statusLabel.text = @"no game";
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.midletStarted) return;
    self.midletStarted = YES;

    // Script-driven runs pass the game in the environment; the library adds
    // sessions through -addGame:width:height:fps:title: instead.
    if (self.sessions.count == 0 && (self.jarPath.length || (g_midlet_jar && g_midlet_jar[0]))) {
        NSString *jar = self.jarPath.length ? self.jarPath : @(g_midlet_jar);
        [self addGame:jar
                width:self.canvasWidth > 0 ? self.canvasWidth : g_width
               height:self.canvasHeight > 0 ? self.canvasHeight : g_height
                  fps:self.fpsLimit > 0 ? self.fpsLimit : g_fps_limit
                title:nil];
    }

    // Synthetic events for automated input verification: prove the ring buffer,
    // the runner's dispatch, and the Canvas callbacks agree. Real touches still
    // arrive through RTGameView's aspect-fit mapping.
    if (getenv("RT_SYNTH_INPUT")) {
        [self scheduleSyntheticEvents];
    }

    // Automation hook: cycle focus between tabs so a scripted run can prove
    // that switching tabs restores the other game's frame.
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
}

- (void)cycleFocus:(NSTimer *)timer {
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

// The scene-based life cycle is mandatory for apps built with current SDKs;
// a legacy UIWindow in the app delegate is rejected at launch.
static int g_shell_mode = 0;

@interface RTSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation RTSceneDelegate

- (void)scene:(UIScene *)scene
        willConnectToSession:(UISceneSession *)session
        options:(UISceneConnectionOptions *)connectionOptions {
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
    UISceneConfiguration *config =
            [[UISceneConfiguration alloc] initWithName:@"Default"
                                           sessionRole:connectingSceneSession.role];
    config.delegateClass = [RTSceneDelegate class];
    return config;
}

@end

// ------------------------------------------------------------ flush bridge

// Optional frame capture. devicectl has no screenshot command and a script
// cannot tap the phone, so the only way to see what the device rendered is to
// have the host write the frames it already receives.
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

// Per-slot frame accounting: fps has to be measured per game, not for the
// process, and the focused log line keeps the old "[RT] ... frames=" shape that
// the run scripts grep for.
static int g_slot_frames[JVM_BRIDGE_MAX_SLOTS];
static double g_slot_started[JVM_BRIDGE_MAX_SLOTS];

/// Every slot reports its frames here; the image reference belongs to this
/// callback. Only the latest frame is kept, for instant redraw on tab switch.
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
        if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS && g_slot_frames[slot] > 0) {
            double elapsed = rt_now() - g_slot_started[slot];
            double fps = elapsed > 0 ? (double) g_slot_frames[slot] / elapsed : 0;
            controller.statusLabel.text =
                    [NSString stringWithFormat:@"%dx%d  %.1f fps", width, height, fps];
        }
        if (g_frames % rt_snapshot_interval() == 0) {
            rt_write_snapshot(cg);
        }
        CGImageRelease(cg);
    });
}

/// The library's navigation controller, so a game session can be pushed from
/// code without the library owning host-controller details.
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
    // Flush callbacks target whichever game screen is on screen.
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
