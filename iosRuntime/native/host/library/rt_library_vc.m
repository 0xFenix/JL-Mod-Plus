// Game library screen: sectioned list of running sessions and installed JARs,
// import from Files, sort, rename, per-game display settings and deletion.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "rt_form_panel.h"
#import "rt_game_store.h"
#import "rt_host.h"
#import "rt_library_vc.h"
#import "rt_theme.h"

#pragma mark - Cells

@interface RTGameCell : UITableViewCell
@property(nonatomic, strong) UIImageView *iconImageView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation RTGameCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = rt_color_surface();
        self.selectedBackgroundView = [[UIView alloc] init];
        self.selectedBackgroundView.backgroundColor = [rt_color_surface_raised() colorWithAlphaComponent:0.6];

        UIImageView *icon = [[UIImageView alloc] init];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.layer.cornerRadius = 14.0;
        icon.layer.cornerCurve = kCACornerCurveContinuous;
        icon.clipsToBounds = YES;
        [self.contentView addSubview:icon];
        self.iconImageView = icon;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = rt_color_text_primary();
        title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
        [self.contentView addSubview:title];
        self.titleLabel = title;

        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.textColor = rt_color_text_secondary();
        subtitle.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
                scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular]];
        [self.contentView addSubview:subtitle];
        self.subtitleLabel = subtitle;

        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:56],
            [icon.heightAnchor constraintEqualToConstant:56],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
            [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

@end

@interface RTRunningCell : UITableViewCell
@property(nonatomic, strong) UIImageView *playImageView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation RTRunningCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = rt_color_surface();
        self.selectedBackgroundView = [[UIView alloc] init];
        self.selectedBackgroundView.backgroundColor = [rt_color_surface_raised() colorWithAlphaComponent:0.6];

        UIImageView *play = [[UIImageView alloc] init];
        play.translatesAutoresizingMaskIntoConstraints = NO;
        play.contentMode = UIViewContentModeScaleAspectFit;
        play.tintColor = rt_color_accent();
        play.image = [UIImage systemImageNamed:@"play.fill"];
        [self.contentView addSubview:play];
        self.playImageView = play;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = rt_color_text_primary();
        title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
        [self.contentView addSubview:title];
        self.titleLabel = title;

        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.textColor = rt_color_text_secondary();
        subtitle.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
                scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular]];
        [self.contentView addSubview:subtitle];
        self.subtitleLabel = subtitle;

        [NSLayoutConstraint activateConstraints:@[
            [play.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [play.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [play.widthAnchor constraintEqualToConstant:28],
            [play.heightAnchor constraintEqualToConstant:28],

            [title.leadingAnchor constraintEqualToAnchor:play.trailingAnchor constant:12],
            [title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
            [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

@end

#pragma mark - Empty state

@interface RTEmptyLibraryView : UIView
@property(nonatomic, copy) void (^importAction)(void);
@end

@implementation RTEmptyLibraryView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *icon = [[UIImageView alloc] init];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tintColor = rt_color_text_tertiary();
        icon.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
        [self addSubview:icon];

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textAlignment = NSTextAlignmentCenter;
        title.numberOfLines = 0;
        title.textColor = rt_color_text_primary();
        title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle2]
                scaledFontForFont:[UIFont systemFontOfSize:22 weight:UIFontWeightSemibold]];
        title.text = @"Chưa có trò chơi nào";
        [self addSubview:title];

        UILabel *body = [[UILabel alloc] init];
        body.translatesAutoresizingMaskIntoConstraints = NO;
        body.textAlignment = NSTextAlignmentCenter;
        body.numberOfLines = 0;
        body.textColor = rt_color_text_secondary();
        body.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightRegular]];
        body.text = @"Nhấn Nhập JAR để chọn file .jar từ ứng dụng Files, hoặc chép file vào thư mục Files › RuntimeApp › games.";
        [self addSubview:body];

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.backgroundColor = rt_color_accent();
        [button setTitle:@"Nhập JAR" forState:UIControlStateNormal];
        [button setTitleColor:rt_color_ink() forState:UIControlStateNormal];
        button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
        button.layer.cornerRadius = 12.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.contentEdgeInsets = UIEdgeInsetsMake(12, 24, 12, 24);
        [button addTarget:self action:@selector(importTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [icon.topAnchor constraintEqualToAnchor:self.topAnchor constant:40],
            [icon.widthAnchor constraintEqualToConstant:64],
            [icon.heightAnchor constraintEqualToConstant:64],

            [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
            [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],

            [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [body.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

            [button.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:24],
            [button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:48],
            [button.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-40],
        ]];
    }
    return self;
}

- (void)importTapped:(UIButton *)sender {
    (void)sender;
    if (self.importAction) self.importAction();
}

@end

#pragma mark - Library

@interface RTLibraryViewController : UITableViewController <UIDocumentPickerDelegate, UIContextMenuInteractionDelegate>
@property(nonatomic, strong) NSArray<RTGameEntry *> *games;
@end

@implementation RTLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gamesChanged:)
                                                 name:@"RTGamesChanged"
                                               object:nil];
    self.title = @"Trò chơi";
    self.view.backgroundColor = rt_color_ink();
    self.tableView.backgroundColor = rt_color_ink();
    self.tableView.separatorColor = rt_color_hairline();
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76;

    // iOS 26 never builds the system large-title label for this bar, so the
    // library draws its own header and keeps the bar for controls only.
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.title = @"";

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 64)];
    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.text = @"Trò chơi";
    headerLabel.textColor = rt_color_text_primary();
    headerLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle]
            scaledFontForFont:[UIFont systemFontOfSize:34 weight:UIFontWeightBold]];
    headerLabel.adjustsFontForContentSizeCategory = YES;
    [header addSubview:headerLabel];
    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [headerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-20],
        [headerLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4],
    ]];
    self.tableView.tableHeaderView = header;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = rt_color_ink();
    appearance.shadowColor = [UIColor clearColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: rt_color_text_primary(),
    };
    appearance.largeTitleTextAttributes = @{
        NSForegroundColorAttributeName: rt_color_text_primary(),
    };

    UIBarButtonItemAppearance *buttonAppearance = [[UIBarButtonItemAppearance alloc] init];
    UIGraphicsImageRenderer *clearRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)];
    UIImage *clearImage = [clearRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    buttonAppearance.normal.backgroundImage = clearImage;
    buttonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: rt_color_accent()};
    [appearance setBackButtonAppearance:buttonAppearance];
    [appearance setDoneButtonAppearance:buttonAppearance];

    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = NO;
    bar.tintColor = rt_color_accent();
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;

    self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(showSortOptions:)];
    self.navigationItem.leftBarButtonItem.tintColor = rt_color_accent();
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"Sắp xếp";

    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(importGame:)];
    self.navigationItem.rightBarButtonItem.tintColor = rt_color_accent();
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Nhập JAR";

    [self.tableView registerClass:[RTGameCell class] forCellReuseIdentifier:@"game"];
    [self.tableView registerClass:[RTRunningCell class] forCellReuseIdentifier:@"running"];

    // No UIRefreshControl: iOS 26 docks it in the navigation bar, which takes
    // the large title slot and leaves the title area blank. The library
    // rescans on every appearance instead.
}

- (void)gamesChanged:(NSNotification *)note {
    (void) note;
    [self reloadGames];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadGames];
    static BOOL openedOnce = NO;
    const char *open_path = getenv("RT_OPEN_JAR");
    if (!openedOnce && open_path && open_path[0]) {
        openedOnce = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            rt_import_jar_path(open_path);
        });
    }
    static BOOL autoLaunched = NO;
    if (!autoLaunched && getenv("RT_AUTOLAUNCH") && self.games.count > 0) {
        autoLaunched = YES;
        BOOL openAll = getenv("RT_AUTOLAUNCH_ALL") != NULL;
        NSArray<RTGameEntry *> *games = self.games.copy;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t) (0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self launchGame:games[0]];
            if (openAll) {
                for (NSUInteger i = 1; i < games.count; i++) {
                    RTGameEntry *entry = games[i];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                    (int64_t) (1.0 * NSEC_PER_SEC * (double) i)),
                                    dispatch_get_main_queue(), ^{
                        [self launchGame:entry];
                    });
                }
            }
        });
    }
}

- (RTGameSortMode)sortMode {
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:RTSortDefaultsKey];
    return stored ? (RTGameSortMode) stored.integerValue : RTGameSortByName;
}

- (NSString *)sortModeTitle {
    switch (self.sortMode) {
        case RTGameSortByLastPlayed:
            return @"Lần chơi cuối";
        case RTGameSortBySize:
            return @"Kích thước";
        case RTGameSortByName:
        default:
            return @"Tên";
    }
}

- (NSString *)lastPlayedPhrase:(NSTimeInterval)interval {
    if (interval <= 0) return @"chưa chơi lần nào";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:interval];
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) return @"đã chơi hôm nay";
    if ([calendar isDateInYesterday:date]) return @"đã chơi hôm qua";
    NSDateComponents *components = [calendar components:NSCalendarUnitDay fromDate:date toDate:now options:0];
    return [NSString stringWithFormat:@"đã chơi %ld ngày trước", (long) MAX(components.day, 2)];
}

- (void)reloadGames {
    self.games = [rt_load_games(self.sortMode).mutableCopy copy];
    [self.tableView reloadData];
    [self updateEmptyState];
    [self.refreshControl endRefreshing];
}

- (void)updateEmptyState {
    if (self.games.count > 0 || rt_host_running_count() > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    RTEmptyLibraryView *empty = [[RTEmptyLibraryView alloc] initWithFrame:self.tableView.bounds];
    __weak typeof(self) weakSelf = self;
    empty.importAction = ^{
        [weakSelf importGame:empty];
    };
    self.tableView.backgroundView = empty;
}

#pragma mark - Sorting

- (void)showSortOptions:(id)sender {
    (void)sender;
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:@"Sắp xếp theo"
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"Tên", @"Lần chơi cuối", @"Kích thước"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *label = titles[i];
        UIAlertAction *action = [UIAlertAction actionWithTitle:label
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                           [[NSUserDefaults standardUserDefaults] setObject:@(i)
                                                                                                     forKey:RTSortDefaultsKey];
                                                           [self reloadGames];
                                                       }];
        if (i == (NSUInteger) self.sortMode) {
            [action setValue:@YES forKey:@"checked"];
        }
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return rt_host_running_count() > 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (rt_host_running_count() > 0 && section == 0) return @"Đang chơi";
    return @"Tất cả trò chơi";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (rt_host_running_count() > 0 && section == 0) return nil;
    NSUInteger count = self.games.count;
    return [NSString stringWithFormat:@"%lu trò chơi, dữ liệu lưu trong ứng dụng", (unsigned long) count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (rt_host_running_count() > 0 && section == 0) return 1;
    return self.games.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 76;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *) view;
        header.textLabel.textColor = rt_color_text_secondary();
        header.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
                scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *) view;
        footer.textLabel.textColor = rt_color_text_tertiary();
        footer.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
                scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular]];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (rt_host_running_count() > 0 && indexPath.section == 0) {
        RTRunningCell *cell = [tableView dequeueReusableCellWithIdentifier:@"running" forIndexPath:indexPath];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        int running = rt_host_running_count();
        cell.titleLabel.text = [NSString stringWithFormat:@"%d trò chơi đang chạy", running];
        cell.subtitleLabel.text = @"Nhấn để tiếp tục";
        return cell;
    }
    RTGameCell *cell = [tableView dequeueReusableCellWithIdentifier:@"game" forIndexPath:indexPath];
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.titleLabel.text = entry.title;
    cell.subtitleLabel.text = entry.detail;
    cell.iconImageView.image = entry.icon;
    if (!cell.iconImageView.image) {
        cell.iconImageView.backgroundColor = rt_color_surface_raised();
        cell.iconImageView.image = [UIImage systemImageNamed:@"gamecontroller"];
        cell.iconImageView.tintColor = rt_color_text_tertiary();
    } else {
        cell.iconImageView.backgroundColor = [UIColor clearColor];
        cell.iconImageView.tintColor = nil;
    }
    if (cell.interactions.count == 0) {
        UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [cell addInteraction:interaction];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (rt_host_running_count() > 0 && indexPath.section == 0) {
        UIViewController *host = (__bridge UIViewController *) rt_host_controller();
        [self.navigationController pushViewController:host animated:YES];
        return;
    }
    [self launchGame:self.games[(NSUInteger) indexPath.row]];
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    if (rt_host_running_count() > 0 && indexPath.section == 0) {
        return;
    }
    [self confirmDeleteOfGame:self.games[(NSUInteger) indexPath.row]];
}

#pragma mark - Context menu

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    (void)location;
    UIView *view = interaction.view;
    UITableViewCell *cell = nil;
    while (view) {
        if ([view isKindOfClass:[UITableViewCell class]]) {
            cell = (UITableViewCell *) view;
            break;
        }
        view = view.superview;
    }
    NSIndexPath *path = [self.tableView indexPathForCell:cell];
    if (!path || (rt_host_running_count() > 0 && path.section == 0)) {
        return nil;
    }
    RTGameEntry *entry = self.games[(NSUInteger) path.row];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"Đổi tên"
                                               image:[UIImage systemImageNamed:@"pencil"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
                                                 [weakSelf promptRenameForGame:entry];
                                             }]];
        [actions addObject:[UIAction actionWithTitle:@"Màn hình và FPS"
                                               image:[UIImage systemImageNamed:@"gearshape"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
                                                 [weakSelf showConfigForGame:entry];
                                             }]];
        [actions addObject:[UIAction actionWithTitle:@"Xoá trò chơi"
                                               image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
                                                 [weakSelf confirmDeleteOfGame:entry];
                                             }]];
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
}

#pragma mark - Launch

- (void)launchGame:(RTGameEntry *)entry {
    NSDictionary *config = rt_game_config(entry.file);
    rt_mark_played(entry.file);
    rt_present_game(entry.path.UTF8String,
                    [config[@"w"] intValue],
                    [config[@"h"] intValue],
                    [config[@"fps"] intValue],
                    entry.title.UTF8String,
                    [config[@"kb"] intValue],
                    [config[@"turbo"] intValue],
                    [config[@"keys"] UTF8String]);
}

#pragma mark - Options

- (void)promptRenameForGame:(RTGameEntry *)entry {
    UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Đổi tên"
                                                message:@"Tên hiển thị trong thư viện."
                                         preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = entry.title;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
                                               NSString *text =
                                                       alert.textFields.firstObject.text;
                                               rt_set_custom_name(entry.file,
                                                                  [text stringByTrimmingCharactersInSet:
                                                                          [NSCharacterSet whitespaceAndNewlineCharacterSet]]);
                                               [self reloadGames];
                                           }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteOfGame:(RTGameEntry *)entry {
    UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Xoá trò chơi?"
                                                message:[NSString stringWithFormat:
                                                        @"Sẽ xoá %@ cùng dữ liệu lưu của nó.", entry.file]
                                         preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xoá"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
                                               [self deleteGame:entry];
                                           }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteGame:(RTGameEntry *)entry {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtPath:entry.path error:NULL];
    // A game can own several save directories: one per tab that ever ran it
    // ("<name>", "<name> 2", ...). They all belong to this JAR.
    NSString *saveRoot = rt_saves_directory();
    NSString *base = entry.file.stringByDeletingPathExtension;
    [manager removeItemAtPath:[saveRoot stringByAppendingPathComponent:base] error:NULL];
    NSString *prefix = [base stringByAppendingString:@" "];
    for (NSString *name in [manager contentsOfDirectoryAtPath:saveRoot error:NULL]) {
        if ([name hasPrefix:prefix]) {
            [manager removeItemAtPath:[saveRoot stringByAppendingPathComponent:name] error:NULL];
        }
    }
    rt_forget_game(entry.file);
    [self reloadGames];
}

#pragma mark - Configuration

- (void)showConfigForGame:(RTGameEntry *)entry {
    NSString *file = entry.file;
    NSDictionary *config = rt_game_config(file);
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:entry.title
                                                message:@"Độ phân giải màn hình"
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    for (int i = 0; i < RT_RESOLUTION_COUNT; i++) {
        RTResolution resolution = RT_RESOLUTIONS[i];
        NSString *label = [NSString stringWithFormat:@"%d × %d", resolution.width, resolution.height];
        BOOL checked = [config[@"w"] intValue] == resolution.width &&
                       [config[@"h"] intValue] == resolution.height;
        UIAlertAction *action = [UIAlertAction actionWithTitle:label
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                           [self setConfig:file
                                                                         w:resolution.width
                                                                         h:resolution.height
                                                                       fps:[config[@"fps"] intValue]
                                                                        kb:[config[@"kb"] intValue]
                                                                     turbo:[config[@"turbo"] intValue]];
                                                       }];
        if (checked) [action setValue:@YES forKey:@"checked"];
        [sheet addAction:action];
    }
    for (NSNumber *fps in @[@0, @30, @60]) {
        NSString *label = fps.intValue == 0 ? @"FPS: không giới hạn"
                                            : [NSString stringWithFormat:@"FPS: %@", fps];
        BOOL checked = [config[@"fps"] intValue] == fps.intValue;
        UIAlertAction *action = [UIAlertAction actionWithTitle:label
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                           [self setConfig:file
                                                                         w:[config[@"w"] intValue]
                                                                         h:[config[@"h"] intValue]
                                                                       fps:fps.intValue
                                                                        kb:[config[@"kb"] intValue]
                                                                     turbo:[config[@"turbo"] intValue]];
                                                       }];
        if (checked) [action setValue:@YES forKey:@"checked"];
        [sheet addAction:action];
    }
    UIAlertAction *keypad = [UIAlertAction
            actionWithTitle:@"Bố cục phím…"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        // Present after the sheet closes, otherwise UIKit
                        // refuses the second presentation.
                        dispatch_async(dispatch_get_main_queue(), ^{
                            rt_present_keypad_editor(self, file, entry.title);
                        });
                    }];
    [sheet addAction:keypad];

    BOOL turbo = [config[@"turbo"] intValue] != 0;
    UIAlertAction *turbAction = [UIAlertAction
            actionWithTitle:(turbo ? @"Turbo khi giữ OK: bật" : @"Turbo khi giữ OK: tắt")
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [self setConfig:file
                                      w:[config[@"w"] intValue]
                                      h:[config[@"h"] intValue]
                                    fps:[config[@"fps"] intValue]
                                     kb:[config[@"kb"] intValue]
                                  turbo:(turbo ? 0 : 1)];
                    }];
    [sheet addAction:turbAction];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setConfig:(NSString *)file w:(int)width h:(int)height fps:(int)fps
               kb:(int)kb turbo:(int)turbo {
    rt_store_game_config(file, @{@"w": @(width), @"h": @(height), @"fps": @(fps),
                                 @"kb": @(kb), @"turbo": @(turbo),
                                 @"keys": rt_game_config(file)[@"keys"] ?: @""});
    [self reloadGames];
}

#pragma mark - Import

- (void)importGame:(id)sender {
    (void)sender;
    UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData]
                                                                       asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
        didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    char *dir_c = rt_games_directory();
    NSString *dir = @(dir_c);
    free(dir_c);
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent;
        if (![[name.pathExtension lowercaseString] isEqualToString:@"jar"]) {
            name = [name stringByAppendingString:@".jar"];
        }
        NSString *destination = [dir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] removeItemAtPath:destination error:NULL];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination]
                                                     error:&error]) {
            NSLog(@"[RT] import failed: %@", error);
        }
    }
    [self reloadGames];
}

@end

int rt_import_jar_path(const char *path) {
    if (!path || !path[0]) {
        return 0;
    }
    NSString *source = @(path);
    if (![[source.pathExtension lowercaseString] isEqualToString:@"jar"]) {
        return 0;
    }
    char *dir_c = rt_games_directory();
    NSString *dir = @(dir_c);
    free(dir_c);
    if (!dir) {
        return 0;
    }

    NSString *base = source.lastPathComponent.stringByDeletingPathExtension;
    NSString *destination = [dir stringByAppendingPathComponent:source.lastPathComponent];
    for (int n = 2; [[NSFileManager defaultManager] fileExistsAtPath:destination]; n++) {
        destination = [dir stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@ %d.jar", base, n]];
    }

    // Files hands over a security-scoped URL; the copy only works inside the
    // scope, and a failure here is the usual cause of an "import does nothing"
    // report.
    NSURL *source_url = [NSURL fileURLWithPath:source];
    BOOL scoped = [source_url startAccessingSecurityScopedResource];
    NSError *error = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:source_url
                                                         toURL:[NSURL fileURLWithPath:destination]
                                                         error:&error];
    if (scoped) {
        [source_url stopAccessingSecurityScopedResource];
    }
    if (!copied) {
        NSLog(@"[RT] open-in import failed: %@", error);
        return 0;
    }
    printf("[RT] imported %s -> %s\n", path, destination.UTF8String);
    fflush(stdout);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RTGamesChanged" object:nil];
    });
    return 1;
}

void *rt_shell_root_controller(void) {
    RTLibraryViewController *library = [[RTLibraryViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:library];
    navigation.navigationBar.prefersLargeTitles = NO;
    navigation.view.backgroundColor = rt_color_ink();
    return (__bridge_retained void *) navigation;
}
