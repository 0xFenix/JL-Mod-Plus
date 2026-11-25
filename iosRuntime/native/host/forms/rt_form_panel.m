// Screen UI for MIDP non-Canvas displays (Form, List, Alert, TextBox).
//
// The Java layer never draws these itself: it pushes a model through the
// NativeBridge.form*/list*/alert* natives (j2me_ui.m keeps it per slot) and
// expects the host to render it and post user actions back through
// j2me_input_post_ui_event(). This file is that host.

#import <UIKit/UIKit.h>

#include "rt_form_panel.h"
#include "rt_theme.h"
#include "j2me_ui.h"
#include "j2me_input.h"

// Item types mirrored from j2me_ui.m's FormItem.
enum {
    RT_ITEM_STRING = 0,
    RT_ITEM_TEXTFIELD = 1,
    RT_ITEM_CHOICE = 2,
    RT_ITEM_IMAGE = 3,
    RT_ITEM_SPACER = 4,
    RT_ITEM_GAUGE = 5,
};

@interface RTFormPanel : UIView <UITextFieldDelegate>
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIStackView *stackView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *listRows;
@property(nonatomic) NSInteger listSelectedIndex;
- (void)rebuildForAction:(int)action;
@end

static __weak UIView *g_host_view = nil;
static RTFormPanel *g_panel = nil;
static void (*g_visibility_callback)(int visible) = NULL;

@implementation RTFormPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // A MIDP screen replaces the canvas, so the panel dims rather than
        // hides what is behind it and reads as a sheet over the game.
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        _listRows = [NSMutableArray array];
        _listSelectedIndex = 0;

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.alwaysBounceVertical = YES;
        [self addSubview:_scrollView];

        // The stack needs a container: the container always fills at least the
        // visible area, while the stack itself stays pinned to its top so short
        // forms read from the top down instead of floating at the bottom.
        UIView *container = [[UIView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;
        [_scrollView addSubview:container];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.spacing = 12;
        [container addSubview:_stackView];

        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        UILayoutGuide *content = _scrollView.contentLayoutGuide;
        UILayoutGuide *frame = _scrollView.frameLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            // Stop above the keyboard so the field being edited stays visible.
            [_scrollView.bottomAnchor constraintEqualToAnchor:self.keyboardLayoutGuide.topAnchor],

            [container.topAnchor constraintEqualToAnchor:content.topAnchor],
            [container.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [container.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
            [container.widthAnchor constraintEqualToAnchor:frame.widthAnchor],
            [container.heightAnchor constraintGreaterThanOrEqualToAnchor:frame.heightAnchor],

            [_stackView.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
            [_stackView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
            [_stackView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
            [_stackView.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-16],
        ]];
    }
    return self;
}

- (UIView *)makeCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = rt_color_surface();
    card.layer.cornerRadius = rt_radius_card();
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    card.layer.borderColor = rt_color_hairline().CGColor;
    card.clipsToBounds = YES;
    return card;
}

- (UIStackView *)makeCardStack:(UIView *)card {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];
    return stack;
}

- (UIView *)makeHairline {
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = rt_color_hairline();
    [line.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale].active = YES;
    return line;
}

- (UILabel *)makeTitleLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.textColor = rt_color_text_primary();
    label.numberOfLines = 0;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    return label;
}

- (UILabel *)makeBodyLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.textColor = rt_color_text_secondary();
    label.numberOfLines = 0;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightRegular]];
    return label;
}

- (UILabel *)makeFieldLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.textColor = rt_color_text_secondary();
    label.numberOfLines = 0;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
            scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular]];
    return label;
}

- (UIButton *)makePrimaryButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:rt_color_ink() forState:UIControlStateNormal];
    button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    button.backgroundColor = rt_color_accent();
    button.layer.cornerRadius = 12.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 20, 14, 20);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    if (action) {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (UITextField *)makeTextField {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = rt_color_surface_raised();
    field.textColor = rt_color_text_primary();
    field.tintColor = rt_color_accent();
    field.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.layer.cornerRadius = 10.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    [field.heightAnchor constraintEqualToConstant:44].active = YES;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    UIView *rightPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    field.leftView = leftPad;
    field.rightView = rightPad;
    field.leftViewMode = UITextFieldViewModeAlways;
    field.rightViewMode = UITextFieldViewModeAlways;
    return field;
}

- (void)clearStack {
    for (UIView *view in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)addSeparatorToStack:(UIStackView *)stack after:(UIView *)view {
    UIView *line = [self makeHairline];
    [stack addArrangedSubview:line];
}

- (void)rebuildForAction:(int)action {
    [self clearStack];

    if (action == J2ME_UI_ACTION_SHOW_ALERT) {
        UIView *card = [self makeCard];
        UIStackView *stack = [self makeCardStack:card];
        const char *text = j2me_ui_get_alert_text();
        [stack addArrangedSubview:[self makeBodyLabel:(text ? @(text) : @"")]];
        UIButton *ok = [self makePrimaryButton:@"OK" action:@selector(dismissAlert:)];
        [stack addArrangedSubview:ok];
        [stack setCustomSpacing:16 afterView:stack.arrangedSubviews[0]];
        [self.stackView addArrangedSubview:card];
        return;
    }

    if (action == J2ME_UI_ACTION_SHOW_TEXTBOX) {
        UIView *card = [self makeCard];
        UIStackView *stack = [self makeCardStack:card];
        const char *title = j2me_ui_get_form_title();
        if (title && title[0]) {
            [stack addArrangedSubview:[self makeTitleLabel:@(title)]];
            [stack setCustomSpacing:14 afterView:stack.arrangedSubviews.lastObject];
        }
        UITextField *field = [self makeTextField];
        const char *text = j2me_ui_get_textbox_text();
        field.text = text ? @(text) : @"";
        field.tag = -1;
        [stack addArrangedSubview:field];
        UIButton *done = [self makePrimaryButton:@"OK" action:@selector(acceptTextBox:)];
        [stack addArrangedSubview:done];
        [stack setCustomSpacing:16 afterView:field];
        [self.stackView addArrangedSubview:card];
        return;
    }

    if (action == J2ME_UI_ACTION_SHOW_LIST) {
        UIView *card = [self makeCard];
        UIStackView *stack = [self makeCardStack:card];
        const char *title = j2me_ui_get_form_title();
        if (title && title[0]) {
            [stack addArrangedSubview:[self makeTitleLabel:@(title)]];
        }
        // Long lists scroll in their own view so the command buttons stay on
        // screen instead of being pushed below dozens of rows.
        UIScrollView *listScroll = [[UIScrollView alloc] init];
        listScroll.translatesAutoresizingMaskIntoConstraints = NO;
        listScroll.showsVerticalScrollIndicator = YES;
        listScroll.alwaysBounceVertical = YES;

        UIStackView *listStack = [[UIStackView alloc] init];
        listStack.translatesAutoresizingMaskIntoConstraints = NO;
        listStack.axis = UILayoutConstraintAxisVertical;
        listStack.spacing = 6;
        [listScroll addSubview:listStack];
        [NSLayoutConstraint activateConstraints:@[
            [listStack.leadingAnchor constraintEqualToAnchor:listScroll.contentLayoutGuide.leadingAnchor],
            [listStack.trailingAnchor constraintEqualToAnchor:listScroll.contentLayoutGuide.trailingAnchor],
            [listStack.topAnchor constraintEqualToAnchor:listScroll.contentLayoutGuide.topAnchor],
            [listStack.bottomAnchor constraintEqualToAnchor:listScroll.contentLayoutGuide.bottomAnchor],
            [listStack.widthAnchor constraintEqualToAnchor:listScroll.frameLayoutGuide.widthAnchor],
            [listScroll.heightAnchor constraintLessThanOrEqualToConstant:360],
        ]];
        // Shrink to the rows while they fit; the <=360 above wins when they do not.
        NSLayoutConstraint *fit = [listScroll.heightAnchor
                constraintEqualToAnchor:listStack.heightAnchor];
        fit.priority = 750;
        fit.active = YES;

        int count = j2me_ui_get_list_item_count();
        if (self.listSelectedIndex < 0 || self.listSelectedIndex >= count) {
            self.listSelectedIndex = 0;
        }
        [self.listRows removeAllObjects];
        for (int i = 0; i < count; i++) {
            const char *item = j2me_ui_get_list_item(i);
            NSString *titleText = item ? @(item) : @"";
            if (j2me_ui_is_list_item_running(i)) {
                titleText = [titleText stringByAppendingString:@"  ▶"];
            }
            UIButton *row = [self makeListRowWithTitle:titleText
                                              selected:(i == self.listSelectedIndex)];
            row.tag = i;
            [self.listRows addObject:row];
            [row addTarget:self action:@selector(selectListRow:) forControlEvents:UIControlEventTouchUpInside];
            // Long-pressing an item opens the command menu, like a handset's
            // context menu; the tapped row becomes the selected one first.
            UILongPressGestureRecognizer *hold =
                    [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                  action:@selector(holdListRow:)];
            hold.minimumPressDuration = 0.35;
            [row addGestureRecognizer:hold];
            [listStack addArrangedSubview:row];
        }
        [stack addArrangedSubview:listScroll];
        [self.stackView addArrangedSubview:card];
        [self addCommandButtons];
        return;
    }

    // SHOW_FORM
    UIView *card = [self makeCard];
    UIStackView *stack = [self makeCardStack:card];
    const char *title = j2me_ui_get_form_title();
    if (title && title[0]) {
        [stack addArrangedSubview:[self makeTitleLabel:@(title)]];
    }
    int count = j2me_ui_get_form_item_count();
    for (int i = 0; i < count; i++) {
        if (stack.arrangedSubviews.count > 0) {
            [self addSeparatorToStack:stack after:nil];
        }
        int type = j2me_ui_get_form_item_type(i);
        const char *label = j2me_ui_get_form_item_label(i);
        const char *text = j2me_ui_get_form_item_text(i);
        NSString *labelText = label ? @(label) : @"";
        NSString *valueText = text ? @(text) : @"";

        if (type == RT_ITEM_TEXTFIELD) {
            if (labelText.length) {
                [stack addArrangedSubview:[self makeFieldLabel:labelText]];
            }
            UITextField *field = [self makeTextField];
            field.text = valueText;
            field.tag = i;
            int constraints = j2me_ui_get_form_item_param2(i);
            if ((constraints & 0x10000) != 0) {
                field.secureTextEntry = YES;
            }
            [stack addArrangedSubview:field];
        } else if (type == RT_ITEM_CHOICE) {
            [self addChoiceGroupForItem:i label:labelText text:valueText inStack:stack];
        } else if (type == RT_ITEM_SPACER) {
            UIView *spacer = [[UIView alloc] init];
            spacer.translatesAutoresizingMaskIntoConstraints = NO;
            [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
            [stack addArrangedSubview:spacer];
        } else if (type != RT_ITEM_IMAGE && type != RT_ITEM_GAUGE) {
            NSString *line = labelText.length
                    ? [NSString stringWithFormat:@"%@\n%@", labelText, valueText]
                    : valueText;
            [stack addArrangedSubview:[self makeBodyLabel:line]];
        }
    }
    [self.stackView addArrangedSubview:card];
    [self addCommandButtons];
}

- (UIButton *)makeChoiceRowWithTitle:(NSString *)title selected:(BOOL)selected {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:44].active = YES;

    UIImageView *indicator = [[UIImageView alloc] init];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.contentMode = UIViewContentModeScaleAspectFit;
    indicator.tintColor = selected ? rt_color_accent() : rt_color_text_secondary();
    indicator.image = [UIImage systemImageNamed:selected ? @"circle.fill" : @"circle"];
    [row addSubview:indicator];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title ?: @"";
    label.textColor = rt_color_text_primary();
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [indicator.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [indicator.widthAnchor constraintEqualToConstant:20],
        [indicator.heightAnchor constraintEqualToConstant:20],

        [label.leadingAnchor constraintEqualToAnchor:indicator.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

- (UIButton *)makeListRowWithTitle:(NSString *)title selected:(BOOL)selected {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setTitle:title ?: @"" forState:UIControlStateNormal];
    row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    row.layer.cornerRadius = 10.0;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self styleListRow:row selected:selected];
    return row;
}

// The selected row keeps the accent so it stands out from the rest of the
// list, the way a handset highlights the current item.
- (void)styleListRow:(UIButton *)row selected:(BOOL)selected {
    [row setTitleColor:(selected ? rt_color_accent() : rt_color_text_primary())
              forState:UIControlStateNormal];
    row.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:16
                                               weight:(selected ? UIFontWeightSemibold
                                                                : UIFontWeightRegular)]];
    row.backgroundColor = selected
            ? [rt_color_accent() colorWithAlphaComponent:0.16] : [UIColor clearColor];
}

- (void)addChoiceGroupForItem:(int)itemIndex label:(NSString *)labelText text:(NSString *)valueText inStack:(UIStackView *)stack {
    if (labelText.length) {
        [stack addArrangedSubview:[self makeFieldLabel:labelText]];
    }
    NSArray<NSString *> *lines = [valueText componentsSeparatedByString:@"\n"];
    NSString *choicesLine = lines.count > 1 ? lines[1] : @"";
    NSString *flagsLine = lines.count > 2 ? lines[2] : @"";
    NSArray<NSString *> *choices = choicesLine.length
            ? [choicesLine componentsSeparatedByString:@"\t"] : @[];
    NSArray<NSString *> *rawFlags = flagsLine.length
            ? [flagsLine componentsSeparatedByString:@","] : @[];
    int selected = lines.count > 0 ? lines[0].intValue : 0;
    BOOL multiple = (j2me_ui_get_form_item_param2(itemIndex) == 2);

    for (NSUInteger c = 0; c < choices.count; c++) {
        BOOL isOn;
        if (multiple) {
            isOn = (c < rawFlags.count &&
                    [rawFlags[c] stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]].intValue == 1);
        } else {
            isOn = ((int) c == selected);
        }
        if (stack.arrangedSubviews.count > 0 && c > 0) {
            [self addSeparatorToStack:stack after:nil];
        }
        UIButton *row = [self makeChoiceRowWithTitle:choices[c] selected:isOn];
        row.tag = itemIndex * 1000 + (int) c;
        [row addTarget:self action:@selector(selectChoiceRow:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:row];
    }
}

- (void)selectChoiceRow:(UIButton *)sender {
    int itemIndex = (int) (sender.tag / 1000);
    int choiceIndex = (int) (sender.tag % 1000);
    const char *text = j2me_ui_get_form_item_text(itemIndex);
    NSArray<NSString *> *lines =
            [(text ? @(text) : @"") componentsSeparatedByString:@"\n"];
    NSString *choicesLine = lines.count > 1 ? lines[1] : @"";
    NSString *flagsLine = lines.count > 2 ? lines[2] : @"";
    NSArray<NSString *> *choices = choicesLine.length
            ? [choicesLine componentsSeparatedByString:@"\t"] : @[];
    NSArray<NSString *> *rawFlags = flagsLine.length
            ? [flagsLine componentsSeparatedByString:@","] : @[];
    BOOL multiple = (j2me_ui_get_form_item_param2(itemIndex) == 2);

    NSMutableArray<NSString *> *flags = [NSMutableArray arrayWithCapacity:choices.count];
    for (NSUInteger c = 0; c < choices.count; c++) {
        BOOL on = (c < rawFlags.count &&
                   [rawFlags[c] stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]].intValue == 1);
        [flags addObject:on ? @"1" : @"0"];
    }
    if (choiceIndex < 0 || choiceIndex >= (int) flags.count) {
        return;
    }
    if (multiple) {
        flags[choiceIndex] = [flags[choiceIndex] isEqualToString:@"1"] ? @"0" : @"1";
    } else {
        for (NSUInteger c = 0; c < flags.count; c++) {
            flags[c] = @"0";
        }
        flags[choiceIndex] = @"1";
    }
    NSString *newText = [NSString stringWithFormat:@"%d\n%@\n%@", choiceIndex,
                         choicesLine, [flags componentsJoinedByString:@","]];
    j2me_ui_set_form_item_text(itemIndex, [newText UTF8String]);
    [self rebuildForAction:J2ME_UI_ACTION_SHOW_FORM];
}

- (UIButton *)makeSecondaryButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:rt_color_text_primary() forState:UIControlStateNormal];
    button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    button.backgroundColor = rt_color_surface_raised();
    button.layer.cornerRadius = 12.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = rt_color_hairline().CGColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 12, 14, 12);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    if (action) {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

// A MIDlet can attach any number of commands to a screen. A single command
// stays a plain button; two or more collapse into one menu button that lists
// them all, the way J2ME Loader does it, so the panel never grows a wall of
// buttons.
// Commands a handset always keeps on screen: OK, Back, Cancel and Exit. Anything
// else (screen/item/help commands) is a menu entry once there is more than one.
static BOOL rt_command_is_primary_type(int type) {
    return type == 2 || type == 3 || type == 4 || type == 7; // Back, Cancel, OK, Exit
}

- (void)addCommandButtons {
    int count = j2me_ui_get_command_count();
    if (count == 0) return;

    NSMutableArray<NSNumber *> *outside = [NSMutableArray array];
    NSMutableArray<NSNumber *> *inside = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        if (rt_command_is_primary_type(j2me_ui_get_command_type(i))) {
            [outside addObject:@(i)];
        } else {
            [inside addObject:@(i)];
        }
    }

    // A screen whose commands are all ordinary keeps the old behaviour: one
    // command is a button, several collapse into the menu.
    if (outside.count == 0) {
        UIView *card = [self makeCard];
        UIStackView *stack = [self makeCardStack:card];
        if (count == 1) {
            const char *label = j2me_ui_get_command_label(0);
            UIButton *primary = [self makePrimaryButton:(label ? @(label) : @"OK")
                                                 action:@selector(fireCommand:)];
            primary.tag = j2me_ui_get_command_id(0);
            [stack addArrangedSubview:primary];
        } else {
            UIButton *menu = [self makePrimaryButton:
                    [NSString stringWithFormat:@"Menu (%d)", count]
                                              action:@selector(showCommandMenu:)];
            [stack addArrangedSubview:menu];
        }
        [self.stackView addArrangedSubview:card];
        return;
    }

    // OK is the natural primary; otherwise the first soft command takes the
    // full-width slot.
    NSUInteger primaryPosition = 0;
    for (NSUInteger i = 0; i < outside.count; i++) {
        if (j2me_ui_get_command_type(outside[i].intValue) == 4) { // Command.OK
            primaryPosition = i;
            break;
        }
    }
    int primaryIndex = outside[primaryPosition].intValue;
    [outside removeObjectAtIndex:primaryPosition];

    UIView *card = [self makeCard];
    UIStackView *stack = [self makeCardStack:card];
    stack.spacing = 10;

    const char *primaryLabel = j2me_ui_get_command_label(primaryIndex);
    UIButton *primary = [self makePrimaryButton:(primaryLabel ? @(primaryLabel) : @"OK")
                                         action:@selector(fireCommand:)];
    primary.tag = j2me_ui_get_command_id(primaryIndex);
    [stack addArrangedSubview:primary];

    // Soft commands and the options menu share the same two-column flow, so a
    // lone button keeps half the width instead of stretching across the card.
    NSUInteger slots = outside.count + (inside.count > 0 ? 1 : 0);
    UIStackView *row = nil;
    for (NSUInteger i = 0; i < slots; i++) {
        if (i % 2 == 0) {
            row = [[UIStackView alloc] init];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.distribution = UIStackViewDistributionFillEqually;
            row.spacing = 10;
            [stack addArrangedSubview:row];
        }
        UIButton *button;
        if (i < outside.count) {
            int index = outside[i].intValue;
            const char *label = j2me_ui_get_command_label(index);
            button = [self makeSecondaryButton:(label ? @(label) : @"")
                                        action:@selector(fireCommand:)];
            button.tag = j2me_ui_get_command_id(index);
        } else {
            button = [self makeSecondaryButton:
                    [NSString stringWithFormat:@"Tùy chọn (%lu)", (unsigned long) inside.count]
                                       action:@selector(showCommandMenu:)];
        }
        [row addArrangedSubview:button];
        if (i % 2 == 0 && i + 1 == slots) {
            [row addArrangedSubview:[[UIView alloc] init]];
        }
    }

    [self.stackView addArrangedSubview:card];
}

- (void)showCommandMenu:(UIView *)sender {
    // Only the commands that did not get a button of their own.
    [self presentCommandMenuFrom:sender includePrimary:NO];
}

- (void)holdListRow:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    UIView *row = hold.view;
    j2me_input_post_ui_event(J2ME_UI_LIST_SET_INDEX, (int) row.tag);
    // Holding a row is a context menu, so it offers every command.
    [self presentCommandMenuFrom:row includePrimary:YES];
}

- (void)presentCommandMenuFrom:(UIView *)anchor includePrimary:(BOOL)includePrimary {
    int count = j2me_ui_get_command_count();
    if (count == 0) return;
    UIViewController *host = self.window.rootViewController;
    while (host.presentedViewController) {
        host = host.presentedViewController;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Tùy chọn"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (int i = 0; i < count; i++) {
        if (!includePrimary && rt_command_is_primary_type(j2me_ui_get_command_type(i))) {
            continue;
        }
        const char *label = j2me_ui_get_command_label(i);
        int commandId = j2me_ui_get_command_id(i);
        [sheet addAction:[UIAlertAction actionWithTitle:(label ? @(label) : @"OK")
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                   [self fireCommandId:commandId];
                                               }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = anchor.bounds;
    [host presentViewController:sheet animated:YES completion:nil];
}

- (void)fireCommandId:(int)commandId {
    [self endEditing:YES];
    j2me_input_post_ui_event(J2ME_UI_COMMAND_ACTION, commandId);
}

- (void)fireCommand:(UIButton *)sender {
    [self fireCommandId:(int) sender.tag];
}

- (void)setListSelection:(NSInteger)index {
    self.listSelectedIndex = index;
    for (UIButton *row in self.listRows) {
        [self styleListRow:row selected:(row.tag == index)];
    }
}

- (void)selectListRow:(UIButton *)sender {
    [self setListSelection:sender.tag];
    j2me_input_post_ui_event(J2ME_UI_LIST_SELECT, (int) sender.tag);
}

- (void)dismissAlert:(UIButton *)sender {
    (void)sender;
    j2me_input_post_ui_event(J2ME_UI_ALERT_DISMISSED, 0);
}

- (void)acceptTextBox:(UIButton *)sender {
    (void)sender;
    for (UIView *view in self.stackView.arrangedSubviews) {
        if (![view isKindOfClass:[UIView class]]) continue;
        for (UIView *inner in ((UIView *) view).subviews) {
            if ([inner isKindOfClass:[UIStackView class]]) {
                for (UIView *fieldOrOther in ((UIStackView *) inner).arrangedSubviews) {
                    if ([fieldOrOther isKindOfClass:[UITextField class]]) {
                        UITextField *field = (UITextField *) fieldOrOther;
                        j2me_ui_set_textbox_text(field.text.length ? [field.text UTF8String] : "");
                        break;
                    }
                }
            }
        }
    }
    [self endEditing:YES];
    int commandId = j2me_ui_get_command_count() > 0 ? j2me_ui_get_command_id(0) : 1;
    j2me_input_post_ui_event(J2ME_UI_COMMAND_ACTION, commandId);
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField.tag >= 0) {
        j2me_ui_set_form_item_text((int) textField.tag,
                textField.text.length ? [textField.text UTF8String] : "");
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

static void rt_ui_callback(int action, const char *data) {
    (void) data;
    dispatch_async(dispatch_get_main_queue(), ^{
        rt_form_ui_present(action);
    });
}

void rt_form_ui_attach(void *host_view) {
    g_host_view = (__bridge UIView *) host_view;
    j2me_ui_set_callback(rt_ui_callback);
}

void rt_form_ui_set_visibility_callback(void (*callback)(int visible)) {
    g_visibility_callback = callback;
}

void rt_form_ui_present(int action) {
    UIView *host = g_host_view;
    if (!host) {
        return;
    }

    if (action == J2ME_UI_ACTION_SHOW_CANVAS) {
        if (g_panel) {
            [g_panel removeFromSuperview];
            g_panel = nil;
        }
        if (g_visibility_callback) g_visibility_callback(0);
        return;
    }

    if (!g_panel) {
        g_panel = [[RTFormPanel alloc] initWithFrame:host.bounds];
        g_panel.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:g_panel];
        [NSLayoutConstraint activateConstraints:@[
            [g_panel.topAnchor constraintEqualToAnchor:host.topAnchor],
            [g_panel.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [g_panel.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [g_panel.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        ]];
    }
    [host bringSubviewToFront:g_panel];
    [g_panel rebuildForAction:action];
    if (g_visibility_callback) g_visibility_callback(1);
}
