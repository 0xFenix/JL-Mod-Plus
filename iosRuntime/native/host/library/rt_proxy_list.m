// Saved SOCKS5 proxy list with the two add flows: one entry at a time and a
// bulk paste of "ip:port:user:pass" lines.
#import <UIKit/UIKit.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

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


#pragma mark - Liveness probe

// shortcut: the probe CONNECTs to 1.1.1.1:80, which needs only a TCP
// handshake. A proxy that filters that address reads as dead even when it
// still works for the game's own server.

static BOOL rt_connect_with_deadline(int fd, const struct sockaddr *addr, socklen_t len, int ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (connect(fd, addr, len) != 0) {
        if (errno != EINPROGRESS) return NO;
        fd_set writable;
        FD_ZERO(&writable);
        FD_SET(fd, &writable);
        struct timeval tv = {ms / 1000, (ms % 1000) * 1000};
        if (select(fd + 1, NULL, &writable, NULL, &tv) <= 0) return NO;
        int error = 0;
        socklen_t error_len = sizeof error;
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &error_len) != 0 || error != 0) return NO;
    }
    fcntl(fd, F_SETFL, flags);
    return YES;
}

static BOOL rt_send_all(int fd, const unsigned char *bytes, size_t length) {
    while (length > 0) {
        ssize_t sent = send(fd, bytes, length, 0);
        if (sent <= 0) return NO;
        bytes += sent;
        length -= (size_t) sent;
    }
    return YES;
}

static BOOL rt_recv_all(int fd, unsigned char *bytes, size_t length) {
    while (length > 0) {
        ssize_t got = recv(fd, bytes, length, 0);
        if (got <= 0) return NO;
        bytes += got;
        length -= (size_t) got;
    }
    return YES;
}

/// Runs an RFC 1928 handshake through the proxy. Returns a short Vietnamese
/// verdict for the list row.
static NSString *rt_probe_proxy(NSDictionary *proxy) {
    NSString *host = proxy[@"host"];
    int port = [proxy[@"port"] intValue];
    NSString *user = proxy[@"user"] ?: @"";
    NSString *pass = proxy[@"pass"] ?: @"";
    NSDate *started = [NSDate date];

    char service[8];
    snprintf(service, sizeof service, "%d", port);
    struct addrinfo hints = {0};
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    struct addrinfo *info = NULL;
    if (getaddrinfo(host.UTF8String, service, &hints, &info) != 0 || info == NULL) {
        return @"Chết · không tìm thấy máy chủ";
    }

    int fd = -1;
    for (struct addrinfo *it = info; it != NULL; it = it->ai_next) {
        int candidate = socket(it->ai_family, it->ai_socktype, 0);
        if (candidate < 0) continue;
        if (rt_connect_with_deadline(candidate, it->ai_addr, it->ai_addrlen, 4000)) {
            fd = candidate;
            break;
        }
        close(candidate);
    }
    freeaddrinfo(info);
    if (fd < 0) return @"Chết · không kết nối được";

    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);

    NSString *verdict = nil;
    do {
        unsigned char greeting[4] = {5, 1, 0, 0};
        if (user.length > 0) {
            greeting[1] = 2;
            greeting[3] = 2;
        }
        unsigned char chosen[2] = {0, 0};
        size_t greetingLength = 2 + greeting[1];
        if (!rt_send_all(fd, greeting, greetingLength) || !rt_recv_all(fd, chosen, 2)) {
            verdict = @"Chết · proxy không trả lời";
            break;
        }
        if (chosen[0] != 5 || chosen[1] == 0xFF) {
            verdict = @"Chết · proxy từ chối kết nối";
            break;
        }
        if (chosen[1] == 2) {
            NSData *userBytes = [user dataUsingEncoding:NSUTF8StringEncoding];
            NSData *passBytes = [pass dataUsingEncoding:NSUTF8StringEncoding];
            if (userBytes.length > 255 || passBytes.length > 255) {
                verdict = @"Chết · tài khoản quá dài";
                break;
            }
            if (user.length == 0) {
                verdict = @"Chết · cần đăng nhập";
                break;
            }
            unsigned char auth[3 + 255 + 255];
            size_t length = 0;
            auth[length++] = 1;
            auth[length++] = (unsigned char) userBytes.length;
            memcpy(auth + length, userBytes.bytes, userBytes.length);
            length += userBytes.length;
            auth[length++] = (unsigned char) passBytes.length;
            memcpy(auth + length, passBytes.bytes, passBytes.length);
            length += passBytes.length;
            unsigned char reply[2] = {0, 0};
            if (!rt_send_all(fd, auth, length) || !rt_recv_all(fd, reply, 2)) {
                verdict = @"Chết · proxy không trả lời";
                break;
            }
            if (reply[1] != 0) {
                verdict = @"Chết · sai tên đăng nhập hoặc mật khẩu";
                break;
            }
        }

        // CONNECT to a public address through the proxy.
        unsigned char request[10] = {5, 1, 0, 1, 1, 1, 1, 1, 0, 80};
        unsigned char head[4] = {0, 0, 0, 0};
        if (!rt_send_all(fd, request, sizeof request) || !rt_recv_all(fd, head, 4)) {
            verdict = @"Chết · proxy không trả lời";
            break;
        }
        if (head[0] != 5 || head[1] != 0) {
            verdict = [NSString stringWithFormat:@"Chết · CONNECT bị từ chối (%d)", head[1]];
            break;
        }
        // Drain the bound address so the socket closes cleanly.
        unsigned char tail[64];
        size_t tailLength = 0;
        if (head[3] == 1) tailLength = 6;
        else if (head[3] == 4) tailLength = 18;
        else if (head[3] == 3) {
            unsigned char nameLength = 0;
            if (rt_recv_all(fd, &nameLength, 1)) tailLength = (size_t) nameLength + 2;
        }
        if (tailLength > 0 && tailLength <= sizeof tail) rt_recv_all(fd, tail, tailLength);

        NSTimeInterval elapsed = -[started timeIntervalSinceNow];
        verdict = [NSString stringWithFormat:@"Sống · %ldms", (long) (elapsed * 1000)];
    } while (0);

    close(fd);
    return verdict;
}

#pragma mark - List

@interface RTProxyListController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *proxies;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *verdicts;
@property(nonatomic) BOOL testing;
@property(nonatomic, strong) UIView *testHeader;
@property(nonatomic, strong) UILabel *testSummaryLabel;
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
    self.verdicts = [NSMutableDictionary dictionary];
    self.testHeader = [self buildTestHeader];
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
    // Test hook: simctl cannot tap, so RT_PROXY_TEST runs the probe for every
    // saved proxy and the [PROXY] log lines are the evidence.
    if (getenv("RT_PROXY_TEST") && self.proxies.count > 0) {
        static BOOL tested = NO;
        if (!tested) {
            tested = YES;
            [self runTests];
        }
    }
}

- (UIView *)buildTestHeader {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 92)];

    UIButton *card = [UIButton buttonWithType:UIButtonTypeSystem];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [rt_color_accent() colorWithAlphaComponent:0.12];
    card.layer.cornerRadius = rt_radius_card();
    card.layer.borderWidth = 1;
    card.layer.borderColor = [rt_color_accent() colorWithAlphaComponent:0.35].CGColor;
    [card addTarget:self action:@selector(runTests) forControlEvents:UIControlEventTouchUpInside];
    card.accessibilityLabel = @"Kiểm tra tất cả proxy";
    [container addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.horizontal.circle"]];
    icon.tintColor = rt_color_accent();
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Kiểm tra tất cả";
    title.textColor = rt_color_accent();
    title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];

    UILabel *summary = [[UILabel alloc] init];
    summary.textColor = rt_color_text_secondary();
    summary.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
            scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular]];
    self.testSummaryLabel = summary;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, summary]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:text];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = rt_color_text_tertiary();
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [text.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];
    return container;
}

- (void)reload {
    self.proxies = rt_proxies();
    [self refreshTestHeader];

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
    self.tableView.tableHeaderView = self.proxies.count > 0 ? self.testHeader : nil;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.proxies.count;
}

- (void)refreshTestHeader {
    self.testSummaryLabel.text = [self testSummary] ?: @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.proxies.count ? @"Đã lưu" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Proxy áp dụng cho mọi kết nối của game. Hỗ trợ SOCKS5; proxy HTTP không dùng được cho game online.";
}

- (NSString *)testSummary {
    if (self.testing) return @"Đang kiểm tra…";
    if (self.proxies.count == 0) return nil;
    NSInteger alive = 0;
    NSInteger dead = 0;
    for (NSDictionary *proxy in self.proxies) {
        NSString *verdict = self.verdicts[proxy[@"id"]];
        if (verdict == nil) continue;
        if ([verdict hasPrefix:@"Sống"]) alive++;
        else dead++;
    }
    if (alive + dead == 0) return @"Chưa kiểm tra";
    return [NSString stringWithFormat:@"%ld sống · %ld chết", (long) alive, (long) dead];
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

    // The verdict replaces the detail line: an accessory would squeeze both
    // texts on a narrow phone.
    NSString *verdict = self.verdicts[proxy[@"id"]];
    if (verdict.length > 0) {
        cell.detailTextLabel.text = verdict;
        cell.detailTextLabel.textColor = [verdict hasPrefix:@"Sống"] ? [UIColor systemGreenColor]
                                                                    : [UIColor systemRedColor];
    }
    return cell;
}

- (void)runTests {
    if (self.testing || self.proxies.count == 0) return;
    self.testing = YES;
    NSArray<NSDictionary *> *batch = self.proxies;
    for (NSDictionary *proxy in batch) {
        self.verdicts[proxy[@"id"]] = @"Đang kiểm tra…";
    }
    [self refreshTestHeader];
    [self.tableView reloadData];
    printf("[PROXY] testing %lu proxies\n", (unsigned long) batch.count);
    fflush(stdout);

    dispatch_group_t group = dispatch_group_create();
    for (NSDictionary *proxy in batch) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *verdict = rt_probe_proxy(proxy);
            printf("[PROXY] test %s -> %s\n", rt_proxy_label(proxy).UTF8String, verdict.UTF8String);
            fflush(stdout);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.verdicts[proxy[@"id"]] = verdict;
                [self refreshTestHeader];
                [self.tableView reloadData];
            });
        });
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        self.testing = NO;
        [self refreshTestHeader];
        [self.tableView reloadData];
    });
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
            [self.verdicts removeObjectForKey:proxy[@"id"]];
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
