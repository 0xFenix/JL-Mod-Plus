// Game surface: framebuffer view with aspect-fit touch mapping plus the
// on-screen MIDP keypad. No JVM state lives here.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include "j2me_input.h"
#include "rt_game_view.h"
#include "rt_theme.h"

// ---------------------------------------------------------------- MIDP keys

#define RT_KEY_UP (-1)
#define RT_KEY_DOWN (-2)
#define RT_KEY_LEFT (-3)
#define RT_KEY_RIGHT (-4)
#define RT_KEY_FIRE (-5)
#define RT_KEY_SOFT1 (-6)
#define RT_KEY_SOFT2 (-7)

static const int rt_keypad_compact[] = {
    RT_KEY_SOFT1, RT_KEY_UP, RT_KEY_SOFT2,
    RT_KEY_LEFT, RT_KEY_FIRE, RT_KEY_RIGHT,
    '*', RT_KEY_DOWN, '#',
};

/// Full phone keypad: the compact controls plus the twelve dial keys, so
/// games that ask for digits can be played without leaving the canvas.
static const int rt_keypad_full[] = {
    RT_KEY_SOFT1, RT_KEY_UP, RT_KEY_SOFT2,
    RT_KEY_LEFT, RT_KEY_FIRE, RT_KEY_RIGHT,
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '*', '0', '#',
};

static const int rt_keypad_cols = 3;

// ---------------------------------------------------------------- game view

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
/// Colour shown when the key is not pressed; highlight derives from it so the
/// amber OK key keeps its identity while pressed.
@property(nonatomic, strong) UIColor *baseBackgroundColor;
@end

@implementation RTKeyButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.baseBackgroundColor = rt_color_surface_raised();
        self.backgroundColor = self.baseBackgroundColor;
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

        // Both the caption and the glyph are centred in the key so the pad
        // reads as one grid instead of labels floating at the top edge.
        [NSLayoutConstraint activateConstraints:@[
            [sub.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [sub.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [sub.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:4],
            [sub.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],

            [symbol.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [symbol.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [symbol.widthAnchor constraintEqualToConstant:22],
            [symbol.heightAnchor constraintEqualToConstant:22],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted
            ? [self.baseBackgroundColor colorWithAlphaComponent:0.72]
            : self.baseBackgroundColor;
}

@end

@interface RTKeypadView ()
@property(nonatomic, strong) UIStackView *column;
@property(nonatomic, strong) NSMutableArray<RTKeyButton *> *buttons;
@property(nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@property(nonatomic, readwrite) BOOL fullKeyboard;
@end

@implementation RTKeypadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];

    self.column = [[UIStackView alloc] init];
    self.column.translatesAutoresizingMaskIntoConstraints = NO;
    self.column.axis = UILayoutConstraintAxisVertical;
    self.column.distribution = UIStackViewDistributionFillEqually;
    self.column.spacing = 8;
    [self addSubview:self.column];

    [NSLayoutConstraint activateConstraints:@[
        [self.column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.column.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [self.column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
    ]];

    self.buttons = [NSMutableArray array];
    [self rebuild];
    return self;
}

- (CGFloat)preferredHeight {
    return self.fullKeyboard ? 340.0 : 190.0;
}

- (void)setFullKeyboard:(BOOL)full {
    if (_fullKeyboard == full) return;
    _fullKeyboard = full;
    [self rebuild];
}

- (void)rebuild {
    for (UIView *row in self.column.arrangedSubviews) {
        [self.column removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    [self.buttons removeAllObjects];

    const int *keys = self.fullKeyboard ? rt_keypad_full : rt_keypad_compact;
    int total = self.fullKeyboard
            ? (int) (sizeof(rt_keypad_full) / sizeof(rt_keypad_full[0]))
            : (int) (sizeof(rt_keypad_compact) / sizeof(rt_keypad_compact[0]));

    for (int row = 0; row * rt_keypad_cols < total; row++) {
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        line.spacing = 8;

        for (int col = 0; col < rt_keypad_cols; col++) {
            int index = row * rt_keypad_cols + col;
            if (index >= total) break;
            RTKeyButton *button = [self makeButtonForMIDPKey:keys[index]];
            [self.buttons addObject:button];
            [line addArrangedSubview:button];
        }
        [self.column addArrangedSubview:line];
    }
}

- (RTKeyButton *)makeButtonForMIDPKey:(int)key {
    RTKeyButton *button = [[RTKeyButton alloc] initWithFrame:CGRectZero];
    button.midpKeyCode = key;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;

    if (key == RT_KEY_FIRE) {
        button.baseBackgroundColor = rt_color_accent();
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
        button.symbolView.hidden = YES;
    } else if (key == RT_KEY_UP || key == RT_KEY_DOWN || key == RT_KEY_LEFT || key == RT_KEY_RIGHT) {
        NSDictionary *symbols = @{
            @(RT_KEY_UP): @"chevron.up",
            @(RT_KEY_DOWN): @"chevron.down",
            @(RT_KEY_LEFT): @"chevron.left",
            @(RT_KEY_RIGHT): @"chevron.right",
        };
        button.detailLabel.hidden = YES;
        button.titleLabel.hidden = YES;
        button.symbolView.image = [UIImage systemImageNamed:symbols[@(key)]];
    } else {
        button.detailLabel.hidden = YES;
        button.symbolView.hidden = YES;
        NSString *title = [NSString stringWithFormat:@"%c", (char) key];
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:rt_color_text_primary() forState:UIControlStateNormal];
    }

    [button addTarget:self
               action:@selector(keyDown:)
     forControlEvents:UIControlEventTouchDown];
    [button addTarget:self
               action:@selector(keyUp:)
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                      UIControlEventTouchCancel];
    return button;
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

