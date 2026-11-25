// Saved SOCKS5 proxy list with the two add flows: one entry at a time and a
// bulk paste of "ip:port:user:pass" lines.
#import <UIKit/UIKit.h>

#import "rt_proxy_list.h"
#import "rt_proxy_store.h"
#import "rt_theme.h"

#pragma mark - Small helpers

static UILabel *rt_proxy_header_label(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = rt_color_text_secondary();
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
            scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular]];
    label.numberOfLines = 0;
    return label;
}

static void rt_style_table(UITableViewController *controller, NSString *title) {
    controller.title = title;
    controller.view.backgroundColor = rt_color_ink();
    controller.tableView.backgroundColor = rt_color_ink();
    controller.tableView.separatorColor = rt_color_hairline();
    controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    controller.navigationController.navigationBar.tintColor = rt_color_accent();
}

#pragma mark - Single proxy form

@interface RTProxyFormController : UITableViewController
@property(nonatomic, strong) UITextField *hostField;
@property(nonatomic, strong) UITextField *portField;
@property(nonatomic, strong) UITextField *userField;
@property(nonatomic, strong) UITextField *passField;
@end

@implementation RTProxyFormController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    rt_style_table(self, @"Proxy mới");
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Lưu"
                                             style:UIBarButtonItemStyleDone
                                            target:self
                                            action:@selector(save:)];
    self.navigationItem.rightBarButtonItem.tintColor = rt_color_accent();

    self.hostField = [self fieldWithPlaceholder:@"1.2.3.4 hoặc proxy.example.com" keyboard:UIKeyboardTypeURL];
    self.portField = [self fieldWithPlaceholder:@"1080" keyboard:UIKeyboardTypeNumberPad];
    self.userField = [self fieldWithPlaceholder:@"Không bắt buộc" keyboard:UIKeyboardTypeDefault];
    self.passField = [self fieldWithPlaceholder:@"Không bắt buộc" keyboard:UIKeyboardTypeDefault];
    self.passField.secureTextEntry = YES;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardType = keyboard;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.textColor = rt_color_text_primary();
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"SOCKS5";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Chỉ hỗ trợ SOCKS5 vì game online không đi qua proxy HTTP.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:nil];
    cell.backgroundColor = rt_color_surface();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSArray<NSString *> *titles = @[@"Địa chỉ", @"Cổng", @"Tên đăng nhập", @"Mật khẩu"];
    UITextField *field = [self fieldForRow:indexPath.row];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = titles[indexPath.row];
    label.textColor = rt_color_text_primary();
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:36],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

- (UITextField *)fieldForRow:(NSInteger)row {
    switch (row) {
        case 0: return self.hostField;
        case 1: return self.portField;
        case 2: return self.userField;
        default: return self.passField;
    }
}

- (void)save:(id)sender {
    (void) sender;
    [self.view endEditing:YES];
    NSString *failure = rt_proxy_add(self.hostField.text,
                                     [self.portField.text intValue],
                                     self.userField.text,
                                     self.passField.text);
    if (failure) {
        UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:@"Chưa lưu được"
                                                    message:failure
                                             preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Bulk paste

@interface RTProxyBulkController : UITableViewController
@property(nonatomic, strong) UITextView *textView;
@end

@implementation RTProxyBulkController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    rt_style_table(self, @"Dán nhiều proxy");
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Lưu"
                                             style:UIBarButtonItemStyleDone
                                            target:self
                                            action:@selector(save:)];
    self.navigationItem.rightBarButtonItem.tintColor = rt_color_accent();

    self.textView = [[UITextView alloc] init];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = rt_color_text_primary();
    self.textView.tintColor = rt_color_accent();
    self.textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.keyboardType = UIKeyboardTypeURL;
    [self.textView becomeFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 220;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:nil];
    cell.backgroundColor = rt_color_surface();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
        [self.textView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        [self.textView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [self.textView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
    ]];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Mỗi dòng một proxy: ip:port:user:pass\nTên đăng nhập và mật khẩu có thể bỏ trống.";
}

- (void)save:(id)sender {
    (void) sender;
    [self.view endEditing:YES];
    NSString *failure = nil;
    NSInteger added = rt_proxy_import(self.textView.text, &failure);
    if (added == 0) {
        UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:@"Chưa lưu được"
                                                    message:failure ?: @"Không có proxy nào hợp lệ."
                                             preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - List

@interface RTProxyListController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *proxies;
@end

@implementation RTProxyListController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    rt_style_table(self, @"Proxy SOCKS5");
    self.tableView.rowHeight = 56;
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(addProxy:)];
    self.navigationItem.rightBarButtonItem.tintColor = rt_color_accent();
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Thêm proxy";
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.proxies = rt_proxies();

    if (self.proxies.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"Chưa có proxy nào.\nThêm proxy SOCKS5 để chọn cho từng game.";
        empty.textColor = rt_color_text_secondary();
        empty.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
                scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightRegular]];
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.frame = self.tableView.bounds;
        self.tableView.backgroundView = empty;
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.proxies.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.proxies.count ? @"Đã lưu" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Proxy áp dụng cho mọi kết nối của game. Hỗ trợ SOCKS5; proxy HTTP không dùng được cho game online.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *proxy = self.proxies[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.backgroundColor = rt_color_surface();
    cell.textLabel.text = rt_proxy_label(proxy);
    cell.textLabel.textColor = rt_color_text_primary();
    cell.detailTextLabel.text = rt_proxy_detail(proxy);
    cell.detailTextLabel.textColor = rt_color_text_secondary();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
        trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *remove =
            [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                    title:@"Xoá"
                                                  handler:^(UIContextualAction *action,
                                                          UIView *sourceView,
                                                          void (^completion)(BOOL)) {
        NSDictionary *proxy = self.proxies[indexPath.row];
        UIAlertController *confirm =
                [UIAlertController alertControllerWithTitle:@"Xoá proxy?"
                                                    message:rt_proxy_label(proxy)
                                             preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Xoá"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction *chosen) {
            rt_proxy_remove(proxy[@"id"]);
            [self reload];
        }]];
        [self presentViewController:confirm animated:YES completion:nil];
        completion(NO);
    }];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)addProxy:(id)sender {
    (void) sender;
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:@"Thêm proxy"
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Nhập từng trường"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[RTProxyFormController alloc] init] animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Dán danh sách"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[RTProxyBulkController alloc] init] animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

void rt_present_proxy_list(UIViewController *host) {
    if (!host.navigationController) return;
    [host.navigationController pushViewController:[[RTProxyListController alloc] init] animated:YES];
}
