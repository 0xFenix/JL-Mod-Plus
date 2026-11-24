// Game library: lists installed JARs, imports them from Files, and keeps
// per-game screen configuration, display name and save data.
//
// Icons come straight out of the JAR (the icon field of MIDlet-1), so a game
// shows up the way it does on a handset without any metadata files of ours.

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "host_form.h"
#import "host_jar.h"
#import "host_shell.h"
#import "host_ui.h"

static NSString *const RTConfigDefaultsKey = @"RTGameConfig";
static NSString *const RTNamesDefaultsKey = @"RTGameNames";
static NSString *const RTLastPlayedDefaultsKey = @"RTGameLastPlayed";
static NSString *const RTSortDefaultsKey = @"RTGameSortMode";

typedef NS_ENUM(NSInteger, RTGameSortMode) {
    RTGameSortByName = 0,
    RTGameSortByLastPlayed = 1,
    RTGameSortBySize = 2,
};

typedef struct {
    int width;
    int height;
} RTResolution;

static const RTResolution RT_RESOLUTIONS[] = {
        {128, 160}, {176, 208}, {240, 320}, {320, 240}, {360, 640}, {480, 800},
};
static const int RT_RESOLUTION_COUNT = 6;

static NSString *rt_documents_directory(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

char *rt_games_directory(void) {
    NSString *path = [rt_documents_directory() stringByAppendingPathComponent:@"games"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return strdup(path.UTF8String);
}

static NSString *rt_saves_directory(void) {
    NSString *path = [rt_documents_directory() stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

#pragma mark - Per-game metadata

static NSDictionary *rt_game_config(NSString *file) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RTConfigDefaultsKey];
    NSDictionary *config = all[file];
    if (config) {
        return config;
    }
    return @{@"w": @240, @"h": @320, @"fps": @0};
}

static void rt_store_game_config(NSString *file, NSDictionary *config) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all =
            [[defaults dictionaryForKey:RTConfigDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[file] = config;
    [defaults setObject:all forKey:RTConfigDefaultsKey];
}

static NSString *rt_custom_name(NSString *file) {
    return [[[NSUserDefaults standardUserDefaults] dictionaryForKey:RTNamesDefaultsKey] objectForKey:file];
}

static void rt_set_custom_name(NSString *file, NSString *name) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all =
            [[defaults dictionaryForKey:RTNamesDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (name.length > 0) {
        all[file] = name;
    } else {
        [all removeObjectForKey:file];
    }
    [defaults setObject:all forKey:RTNamesDefaultsKey];
}

static NSTimeInterval rt_last_played(NSString *file) {
    NSNumber *value = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:RTLastPlayedDefaultsKey] objectForKey:file];
    return value ? value.doubleValue : 0;
}

static void rt_mark_played(NSString *file) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all =
            [[defaults dictionaryForKey:RTLastPlayedDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[file] = @([[NSDate date] timeIntervalSince1970]);
    [defaults setObject:all forKey:RTLastPlayedDefaultsKey];
}

/// Forgets everything we stored about a game that is being removed.
static void rt_forget_game(NSString *file) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[RTConfigDefaultsKey, RTNamesDefaultsKey, RTLastPlayedDefaultsKey]) {
        NSMutableDictionary *all = [[defaults dictionaryForKey:key] mutableCopy];
        if (!all[file]) {
            continue;
        }
        [all removeObjectForKey:file];
        [defaults setObject:all forKey:key];
    }
}

#pragma mark - Icons

static UIImage *rt_scaled_icon(UIImage *icon) {
    CGSize size = CGSizeMake(40, 40);
    UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                   format:[UIGraphicsImageRendererFormat defaultFormat]];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationNone);
        [icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

/// Reads the MIDlet-1 icon entry out of the JAR and scales it for a table cell.
static UIImage *rt_game_icon(NSString *jarPath, const char *midlet) {
    char icon[256] = {0};
    if (!rt_jar_midlet_icon(midlet, icon, sizeof(icon))) {
        return nil;
    }
    size_t length = 0;
    unsigned char *bytes = rt_jar_extract_entry(jarPath.UTF8String, icon, &length);
    if (!bytes) {
        return nil;
    }
    NSData *data = [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES];
    UIImage *image = [UIImage imageWithData:data];
    return image ? rt_scaled_icon(image) : nil;
}

#pragma mark - Model

@interface RTGameEntry : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *file;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, strong) UIImage *icon;
@property(nonatomic) NSTimeInterval lastPlayed;
@property(nonatomic) unsigned long long size;
@end

@implementation RTGameEntry
@end

@interface RTLibraryViewController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) NSArray<RTGameEntry *> *games;
@end

@implementation RTLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trò chơi";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView.rowHeight = 64;
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                          target:self
                                                          action:@selector(importGame:)];
    self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Sắp xếp"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(showSortOptions:)];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(reloadGames) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadGames];
    // Automation hook: the simulator has no tap API, so tests set
    // RT_AUTOLAUNCH=1 to open the first game without touching the screen.
    static BOOL autoLaunched = NO;
    if (!autoLaunched && getenv("RT_AUTOLAUNCH") && self.games.count > 0) {
        autoLaunched = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t) (0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self launchGame:self.games[0]];
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

- (void)reloadGames {
    char *dir_c = rt_games_directory();
    NSString *dir = @(dir_c);
    free(dir_c);

    NSArray<NSString *> *files =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray<RTGameEntry *> *entries = [NSMutableArray array];
    for (NSString *file in files) {
        if (![[file.pathExtension lowercaseString] isEqualToString:@"jar"]) {
            continue;
        }
        NSString *path = [dir stringByAppendingPathComponent:file];
        char name[192] = {0};
        char midlet[512] = {0};
        rt_jar_read_manifest(path.UTF8String, name, sizeof(name), midlet, sizeof(midlet));

        RTGameEntry *entry = [[RTGameEntry alloc] init];
        entry.path = path;
        entry.file = file;
        NSString *custom = rt_custom_name(file);
        entry.title = custom.length ? custom : (name[0] ? @(name) : file.stringByDeletingPathExtension);
        entry.icon = rt_game_icon(path, midlet);
        entry.lastPlayed = rt_last_played(file);
        entry.size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize] ?: 0;

        NSDictionary *config = rt_game_config(file);
        entry.detail = [NSString stringWithFormat:@"%@  ·  %@×%@%@", file,
                                                  config[@"w"], config[@"h"],
                                                  [config[@"fps"] intValue] > 0
                                                          ? [NSString stringWithFormat:@"  ·  %@ fps", config[@"fps"]]
                                                          : @""];
        [entries addObject:entry];
    }

    RTGameSortMode mode = self.sortMode;
    [entries sortUsingComparator:^NSComparisonResult(RTGameEntry *a, RTGameEntry *b) {
        switch (mode) {
            case RTGameSortByLastPlayed:
                if (a.lastPlayed != b.lastPlayed) {
                    return a.lastPlayed > b.lastPlayed ? NSOrderedAscending : NSOrderedDescending;
                }
                break;
            case RTGameSortBySize:
                if (a.size != b.size) {
                    return a.size > b.size ? NSOrderedAscending : NSOrderedDescending;
                }
                break;
            case RTGameSortByName:
            default:
                break;
        }
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    self.games = entries;
    [self.tableView reloadData];
    [self updateEmptyState];
    [self.refreshControl endRefreshing];
}

- (void)updateEmptyState {
    if (self.games.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.text = @"Chưa có trò chơi.\nNhấn + để thêm file .jar\n(hoặc chép vào thư mục Files › RuntimeApp › games).";
    self.tableView.backgroundView = label;
}

#pragma mark - Sorting

- (void)showSortOptions:(id)sender {
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:@"Sắp xếp theo"
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"Tên", @"Lần chơi cuối", @"Kích thước"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *label = i == (NSUInteger) self.sortMode
                ? [titles[i] stringByAppendingString:@"  ✓"] : titles[i];
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                   [[NSUserDefaults standardUserDefaults] setObject:@(i)
                                                                                             forKey:RTSortDefaultsKey];
                                                   [self reloadGames];
                                               }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.games.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"game";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    }
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    cell.textLabel.text = entry.title;
    cell.detailTextLabel.text = entry.detail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.imageView.image = entry.icon;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    [self launchGame:entry];
}

- (void)tableView:(UITableView *)tableView
        accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    [self showOptionsForGame:entry];
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    [self confirmDeleteOfGame:entry];
}

#pragma mark - Launch

- (void)launchGame:(RTGameEntry *)entry {
    NSDictionary *config = rt_game_config(entry.file);
    rt_mark_played(entry.file);
    void *controller = rt_create_game_controller(entry.path.UTF8String,
                                                 [config[@"w"] intValue],
                                                 [config[@"h"] intValue],
                                                 [config[@"fps"] intValue]);
    UIViewController *game = (__bridge_transfer UIViewController *) controller;
    [self.navigationController pushViewController:game animated:YES];
}

#pragma mark - Options

- (void)showOptionsForGame:(RTGameEntry *)entry {
    UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:entry.title
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Đổi tên"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
                                               [self promptRenameForGame:entry];
                                           }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Màn hình & FPS"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
                                               [self showConfigForGame:entry];
                                           }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Xoá trò chơi"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
                                               [self confirmDeleteOfGame:entry];
                                           }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

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
    NSString *saveDirectory = [rt_saves_directory()
            stringByAppendingPathComponent:entry.file.stringByDeletingPathExtension];
    [manager removeItemAtPath:saveDirectory error:NULL];
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
        if ([config[@"w"] intValue] == resolution.width &&
            [config[@"h"] intValue] == resolution.height) {
            label = [label stringByAppendingString:@"  ✓"];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                   [self setConfig:file
                                                                 w:resolution.width
                                                                 h:resolution.height
                                                               fps:[config[@"fps"] intValue]];
                                               }]];
    }
    for (NSNumber *fps in @[@0, @30, @60]) {
        NSString *label = fps.intValue == 0 ? @"FPS: không giới hạn"
                                            : [NSString stringWithFormat:@"FPS: %@", fps];
        if ([config[@"fps"] intValue] == fps.intValue) {
            label = [label stringByAppendingString:@"  ✓"];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                   [self setConfig:file
                                                                 w:[config[@"w"] intValue]
                                                                 h:[config[@"h"] intValue]
                                                               fps:fps.intValue];
                                               }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setConfig:(NSString *)file w:(int)width h:(int)height fps:(int)fps {
    rt_store_game_config(file, @{@"w": @(width), @"h": @(height), @"fps": @(fps)});
    [self reloadGames];
}

#pragma mark - Import

- (void)importGame:(id)sender {
    UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData]
                                                                       asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
        didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
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

void *rt_shell_root_controller(void) {
    RTLibraryViewController *library = [[RTLibraryViewController alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:library];
    return (__bridge_retained void *) navigation;
}
