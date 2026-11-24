// Screen UI for MIDP non-Canvas displays (Form, List, Alert, TextBox).
//
// The Java layer never draws these itself: it pushes a model through the
// NativeBridge.form*/list*/alert* natives (j2me_ui.m keeps it per slot) and
// expects the host to render it and post user actions back through
// j2me_input_post_ui_event(). This file is that host.

#import <UIKit/UIKit.h>

#include "host_form.h"
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

@implementation RTFormPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.alwaysBounceVertical = YES;
        [self addSubview:_scrollView];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.spacing = 8;
        [_scrollView addSubview:_stackView];

        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

            [_stackView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:12],
            [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor constant:12],
            [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor constant:-12],
            [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-12],
            [_stackView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor constant:-24],
        ]];
    }
    return self;
}

- (UILabel *)makeLabel:(NSString *)text bold:(BOOL)bold {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.textColor = [UIColor whiteColor];
    label.numberOfLines = 0;
    label.font = bold ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:15];
    return label;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title ?: @"OK" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16];
    button.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    button.layer.cornerRadius = 6;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 14, 10, 14);
    if (action) {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (void)clearStack {
    for (UIView *view in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)rebuildForAction:(int)action {
    [self clearStack];

    if (action == J2ME_UI_ACTION_SHOW_ALERT) {
        const char *text = j2me_ui_get_alert_text();
        [self.stackView addArrangedSubview:[self makeLabel:(text ? @(text) : @"") bold:NO]];
        UIButton *ok = [self makeButton:@"OK" action:@selector(dismissAlert:)];
        [self.stackView addArrangedSubview:ok];
        return;
    }

    if (action == J2ME_UI_ACTION_SHOW_TEXTBOX) {
        const char *title = j2me_ui_get_form_title();
        if (title && title[0]) {
            [self.stackView addArrangedSubview:[self makeLabel:@(title) bold:YES]];
        }
        UITextField *field = [self makeTextField];
        const char *text = j2me_ui_get_textbox_text();
        field.text = text ? @(text) : @"";
        field.tag = -1; // not a Form item
        [self.stackView addArrangedSubview:field];
        UIButton *done = [self makeButton:@"OK" action:@selector(acceptTextBox:)];
        [self.stackView addArrangedSubview:done];
        return;
    }

    if (action == J2ME_UI_ACTION_SHOW_LIST) {
        const char *title = j2me_ui_get_form_title();
        if (title && title[0]) {
            [self.stackView addArrangedSubview:[self makeLabel:@(title) bold:YES]];
        }
        int count = j2me_ui_get_list_item_count();
        for (int i = 0; i < count; i++) {
            const char *item = j2me_ui_get_list_item(i);
            NSString *titleText = item ? @(item) : @"";
            if (j2me_ui_is_list_item_running(i)) {
                titleText = [titleText stringByAppendingString:@"  ▶"];
            }
            UIButton *row = [self makeButton:titleText action:@selector(selectListRow:)];
            row.tag = i;
            row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            [self.stackView addArrangedSubview:row];
        }
        [self addCommandButtons];
        return;
    }

    // SHOW_FORM (default): title, items, commands.
    const char *title = j2me_ui_get_form_title();
    if (title && title[0]) {
        [self.stackView addArrangedSubview:[self makeLabel:@(title) bold:YES]];
    }
    int count = j2me_ui_get_form_item_count();
    for (int i = 0; i < count; i++) {
        int type = j2me_ui_get_form_item_type(i);
        const char *label = j2me_ui_get_form_item_label(i);
        const char *text = j2me_ui_get_form_item_text(i);
        NSString *labelText = label ? @(label) : @"";
        NSString *valueText = text ? @(text) : @"";

        if (type == RT_ITEM_TEXTFIELD) {
            if (labelText.length) {
                [self.stackView addArrangedSubview:[self makeLabel:labelText bold:NO]];
            }
            UITextField *field = [self makeTextField];
            field.text = valueText;
            field.tag = i;
            int constraints = j2me_ui_get_form_item_param2(i);
            // MIDP TextField.PASSWORD == 0x10000
            if ((constraints & 0x10000) != 0) {
                field.secureTextEntry = YES;
            }
            [self.stackView addArrangedSubview:field];
        } else if (type == RT_ITEM_CHOICE) {
            [self addChoiceGroupForItem:i label:labelText text:valueText];
        } else if (type == RT_ITEM_SPACER) {
            UIView *spacer = [[UIView alloc] init];
            [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
            [self.stackView addArrangedSubview:spacer];
        } else if (type != RT_ITEM_IMAGE && type != RT_ITEM_GAUGE) {
            NSString *line = labelText.length
                    ? [NSString stringWithFormat:@"%@\n%@", labelText, valueText]
                    : valueText;
            [self.stackView addArrangedSubview:[self makeLabel:line bold:NO]];
        }
    }
    [self addCommandButtons];
}

- (UITextField *)makeTextField {
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.backgroundColor = [UIColor whiteColor];
    field.textColor = [UIColor blackColor];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    [field.heightAnchor constraintEqualToConstant:34].active = YES;
    return field;
}

// Render a ChoiceGroup as tappable option rows. Java serializes it as
// "<selectedIndex>\n<choice1>\t<choice2>...\n<flag1>,<flag2>..." (see
// Form.showNative), so the selection lives in the item text and is read back
// by Form.syncFromNative when a command fires.
- (void)addChoiceGroupForItem:(int)itemIndex label:(NSString *)labelText text:(NSString *)valueText {
    if (labelText.length) {
        [self.stackView addArrangedSubview:[self makeLabel:labelText bold:NO]];
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
        NSString *rowTitle = [NSString stringWithFormat:@"%@  %@", isOn ? @"●" : @"○", choices[c]];
        UIButton *row = [self makeButton:rowTitle action:@selector(selectChoiceRow:)];
        row.tag = itemIndex * 1000 + (int) c;
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [self.stackView addArrangedSubview:row];
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
    for (int i = 0; i < count; i++) {
        const char *label = j2me_ui_get_command_label(i);
        UIButton *button = [self makeButton:(label ? @(label) : @"OK")
                                     action:@selector(fireCommand:)];
        button.tag = j2me_ui_get_command_id(i);
        [self.stackView addArrangedSubview:button];
    }
}

- (void)fireCommand:(UIButton *)sender {
    [self endEditing:YES];
    j2me_input_post_ui_event(J2ME_UI_COMMAND_ACTION, (int) sender.tag);
}

- (void)selectListRow:(UIButton *)sender {
    j2me_input_post_ui_event(J2ME_UI_LIST_SELECT, (int) sender.tag);
}

- (void)dismissAlert:(UIButton *)sender {
    j2me_input_post_ui_event(J2ME_UI_ALERT_DISMISSED, 0);
}

- (void)acceptTextBox:(UIButton *)sender {
    for (UIView *view in self.stackView.arrangedSubviews) {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *) view;
            j2me_ui_set_textbox_text(field.text.length ? [field.text UTF8String] : "");
            break;
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
    // Called from the JVM thread; UIKit work belongs on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        rt_form_ui_present(action);
    });
}

void rt_form_ui_attach(void *host_view) {
    g_host_view = (__bridge UIView *) host_view;
    j2me_ui_set_callback(rt_ui_callback);
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
}
