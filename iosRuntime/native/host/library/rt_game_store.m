// Library data: the installed JARs, their manifest-derived titles and icons,
// per-game configuration, and the small amount of bookkeeping (custom name,
// last played) kept in NSUserDefaults. Nothing here touches UIKit views or the
// JVM.
#import <UIKit/UIKit.h>

#import "rt_jar_manifest.h"
#import "rt_proxy_store.h"

static NSString *const RTConfigDefaultsKey = @"RTGameConfig";
static NSString *const RTNamesDefaultsKey = @"RTGameNames";
static NSString *const RTLastPlayedDefaultsKey = @"RTGameLastPlayed";
NSString *const RTSortDefaultsKey = @"RTGameSortMode";

typedef NS_ENUM(NSInteger, RTGameSortMode) {
    RTGameSortByName = 0,
    RTGameSortByLastPlayed = 1,
    RTGameSortBySize = 2,
};

typedef struct {
    int width;
    int height;
} RTResolution;

const RTResolution RT_RESOLUTIONS[] = {
        {128, 160}, {176, 208}, {240, 320}, {320, 240}, {360, 640}, {480, 800},
};
const int RT_RESOLUTION_COUNT = 6;

NSString *rt_documents_directory(void) {
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

NSString *rt_saves_directory(void) {
    NSString *path = [rt_documents_directory() stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

#pragma mark - Per-game metadata

NSDictionary *rt_game_config(NSString *file) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RTConfigDefaultsKey];
    NSDictionary *config = all[file];
    if (config) {
        return config;
    }
    return @{@"w": @240, @"h": @320, @"fps": @0, @"kb": @0, @"turbo": @0,
             @"keys": @"", @"proxy": @""};
}

void rt_store_game_config(NSString *file, NSDictionary *config) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all =
            [[defaults dictionaryForKey:RTConfigDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[file] = config;
    [defaults setObject:all forKey:RTConfigDefaultsKey];
    // A proxy picked in a tab must survive the app being closed right away.
    [defaults synchronize];
}

void rt_set_game_keys(NSString *file, NSString *keys) {
    NSMutableDictionary *config = [rt_game_config(file) mutableCopy];
    config[@"keys"] = keys ?: @"";
    rt_store_game_config(file, config);
}

void rt_set_game_proxy(NSString *file, NSString *proxyId) {
    NSMutableDictionary *config = [rt_game_config(file) mutableCopy];
    config[@"proxy"] = proxyId ?: @"";
    rt_store_game_config(file, config);
}

NSArray<NSString *> *rt_game_slot_proxies(NSString *file) {
    id slots = rt_game_config(file)[@"slots"];
    return [slots isKindOfClass:[NSArray class]] ? slots : @[];
}

void rt_set_game_slot_proxy(NSString *file, NSUInteger index, NSString *proxyId) {
    NSMutableDictionary *config = [rt_game_config(file) mutableCopy];
    NSMutableArray<NSString *> *slots = [(config[@"slots"] ?: @[]) mutableCopy];
    while (slots.count <= index) {
        [slots addObject:@""];
    }
    slots[index] = proxyId ?: @"";
    config[@"slots"] = slots;
    rt_store_game_config(file, config);
}

NSString *rt_custom_name(NSString *file) {
    return [[[NSUserDefaults standardUserDefaults] dictionaryForKey:RTNamesDefaultsKey] objectForKey:file];
}

void rt_set_custom_name(NSString *file, NSString *name) {
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

NSTimeInterval rt_last_played(NSString *file) {
    NSNumber *value = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:RTLastPlayedDefaultsKey] objectForKey:file];
    return value ? value.doubleValue : 0;
}

void rt_mark_played(NSString *file) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all =
            [[defaults dictionaryForKey:RTLastPlayedDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[file] = @([[NSDate date] timeIntervalSince1970]);
    [defaults setObject:all forKey:RTLastPlayedDefaultsKey];
}

/// Forgets everything we stored about a game that is being removed.
void rt_forget_game(NSString *file) {
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
    CGSize size = CGSizeMake(56, 56);
    UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                   format:[UIGraphicsImageRendererFormat defaultFormat]];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationNone);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                        cornerRadius:14.0];
        [path addClip];
        [icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

/// Reads the MIDlet-1 icon entry out of the JAR and scales it for a table cell.
UIImage *rt_game_icon(NSString *jarPath, const char *midlet) {
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


/// "3 ngày trước"-style wording for the library subtitle.
NSString *rt_last_played_phrase(NSTimeInterval interval) {
    if (interval <= 0) {
        return @"chưa chơi";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:interval];
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) return @"đã chơi hôm nay";
    if ([calendar isDateInYesterday:date]) return @"đã chơi hôm qua";
    NSDateComponents *components = [calendar components:NSCalendarUnitDay fromDate:date toDate:now options:0];
    return [NSString stringWithFormat:@"đã chơi %ld ngày trước", (long) MAX(components.day, 2)];
}

NSArray<RTGameEntry *> *rt_load_games(RTGameSortMode mode) {
    char *dir_c = rt_games_directory();
    NSString *dir = @(dir_c);
    free(dir_c);

    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
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
        NSString *fpsPart = [config[@"fps"] intValue] > 0
                ? [NSString stringWithFormat:@", %@ fps", config[@"fps"]]
                : @"";
        NSString *proxyPart = @"";
        NSDictionary *proxy = [config[@"proxy"] length] > 0
                ? rt_proxy_with_id(config[@"proxy"])
                : nil;
        if (proxy) {
            // Ahead of the last-played phrase: the proxy is a setting the row
            // must still show when the subtitle truncates.
            proxyPart = [NSString stringWithFormat:@", qua %@", rt_proxy_label(proxy)];
        }
        entry.detail = [NSString stringWithFormat:@"%@×%@%@%@, %@",
                                                  config[@"w"], config[@"h"],
                                                  fpsPart, proxyPart,
                                                  rt_last_played_phrase(entry.lastPlayed)];
        [entries addObject:entry];
    }

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
    return entries;
}
