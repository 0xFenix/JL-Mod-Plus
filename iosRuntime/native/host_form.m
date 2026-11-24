// Screen UI for MIDP non-Canvas displays (Form, List, Alert, TextBox).
//
// The Java layer never draws these itself: it pushes a model through the
// NativeBridge.form*/list*/alert* natives (j2me_ui.m keeps it per slot) and
// expects the host to render it and post user actions back through
// j2me_input_post_ui_event(). This file is that host.

#import <UIKit/UIKit.h>

#include "host_form.h"
#include "host_theme.h"
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

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.alwaysBounceVertical = YES;
        [self addSubview:_scrollView];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.spacing = 12;
        [_scrollView addSubview:_stackView];

        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

            // Bottom-anchored like a sheet: short forms sit above the home
            // indicator, long ones grow upward and scroll.
            [_stackView.topAnchor constraintGreaterThanOrEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor
                                                              constant:16],
            [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor constant:16],
            [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor constant:-16],
            [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-16],
            [_stackView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor constant:-32],
            [_scrollView.contentLayoutGuide.heightAnchor
                    constraintGreaterThanOrEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor],
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
        int count = j2me_ui_get_list_item_count();
        for (int i = 0; i < count; i++) {
            if (stack.arrangedSubviews.count > 0) {
                [self addSeparatorToStack:stack after:nil];
            }
            const char *item = j2me_ui_get_list_item(i);
            NSString *titleText = item ? @(item) : @"";
            if (j2me_ui_is_list_item_running(i)) {
                titleText = [titleText stringByAppendingString:@"  ▶"];
            }
            UIButton *row = [self makeChoiceRowWithTitle:titleText selected:NO];
            row.tag = i;
            [row addTarget:self action:@selector(selectListRow:) forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:row];
        }
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

- (void)addCommandButtons {
    int count = j2me_ui_get_command_count();
    if (count == 0) return;
    UIView *card = [self makeCard];
    UIStackView *stack = [self makeCardStack:card];
    for (int i = 0; i < count; i++) {
        const char *label = j2me_ui_get_command_label(i);
        UIButton *button = [self makePrimaryButton:(label ? @(label) : @"OK")
                                            action:@selector(fireCommand:)];
        button.tag = j2me_ui_get_command_id(i);
        if (i > 0) {
            [stack setCustomSpacing:10 afterView:stack.arrangedSubviews.lastObject];
        }
        [stack addArrangedSubview:button];
    }
    [self.stackView addArrangedSubview:card];
}

- (void)fireCommand:(UIButton *)sender {
    [self endEditing:YES];
    j2me_input_post_ui_event(J2ME_UI_COMMAND_ACTION, (int) sender.tag);
}

- (void)selectListRow:(UIButton *)sender {
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
