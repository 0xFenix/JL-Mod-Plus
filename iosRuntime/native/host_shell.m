// Game library: lists installed JARs, imports them from Files, keeps a
// per-game screen configuration and pushes the game screen.

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "host_form.h"
#import "host_jar.h"
#import "host_shell.h"
#import "host_ui.h"

static NSString *const RTConfigDefaultsKey = @"RTGameConfig";

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

@interface RTGameEntry : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
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
    self.tableView.rowHeight = 58;
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                          target:self
                                                          action:@selector(importGame:)];
    self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Tải lại"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(reloadGames)];
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
        entry.title = name[0] ? @(name) : file.stringByDeletingPathExtension;
        NSDictionary *config = rt_game_config(file);
        entry.detail = [NSString stringWithFormat:@"%@  ·  %@×%@%@", file,
                                                  config[@"w"], config[@"h"],
                                                  [config[@"fps"] intValue] > 0
                                                          ? [NSString stringWithFormat:@"  ·  %@ fps", config[@"fps"]]
                                                          : @""];
        [entries addObject:entry];
    }
    [entries sortUsingComparator:^NSComparisonResult(RTGameEntry *a, RTGameEntry *b) {
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    self.games = entries;
    self.navigationItem.leftBarButtonItem.enabled = YES;
    [self.tableView reloadData];
    [self updateEmptyState];
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
    }
    RTGameEntry *entry = self.games[(NSUInteger) indexPath.row];
    cell.textLabel.text = entry.title;
    cell.detailTextLabel.text = entry.detail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
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
    [self showConfigForGame:entry];
}

#pragma mark - Launch

- (void)launchGame:(RTGameEntry *)entry {
    NSString *file = entry.path.lastPathComponent;
    NSDictionary *config = rt_game_config(file);
    void *controller = rt_create_game_controller(entry.path.UTF8String,
                                                 [config[@"w"] intValue],
                                                 [config[@"h"] intValue],
                                                 [config[@"fps"] intValue]);
    UIViewController *game = (__bridge_transfer UIViewController *) controller;
    [self.navigationController pushViewController:game animated:YES];
}

#pragma mark - Configuration

- (void)showConfigForGame:(RTGameEntry *)entry {
    NSString *file = entry.path.lastPathComponent;
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
    picker.allowsMultipleSelection = NO;
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
