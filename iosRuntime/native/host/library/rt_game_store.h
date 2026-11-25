// Library data model and per-game settings. The library view controller is the
// only consumer; nothing here depends on a running JVM.
#import <UIKit/UIKit.h>

extern NSString *const RTSortDefaultsKey;

typedef NS_ENUM(NSInteger, RTGameSortMode) {
    RTGameSortByName = 0,
    RTGameSortByLastPlayed = 1,
    RTGameSortBySize = 2,
};

typedef struct {
    int width;
    int height;
} RTResolution;

extern const RTResolution RT_RESOLUTIONS[];
extern const int RT_RESOLUTION_COUNT;

@interface RTGameEntry : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *file;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, strong) UIImage *icon;
@property(nonatomic) NSTimeInterval lastPlayed;
@property(nonatomic) unsigned long long size;
@end

/// <Documents>/games, created on demand. Caller frees.
char *rt_games_directory(void);
/// <Documents>/save, created on demand.
NSString *rt_saves_directory(void);
NSDictionary *rt_game_config(NSString *file);
void rt_store_game_config(NSString *file, NSDictionary *config);
/// Stores only the custom keypad layout, leaving the rest of the config alone.
void rt_set_game_keys(NSString *file, NSString *keys);
NSString *rt_custom_name(NSString *file);
void rt_set_custom_name(NSString *file, NSString *name);
NSTimeInterval rt_last_played(NSString *file);
void rt_mark_played(NSString *file);
void rt_forget_game(NSString *file);
/// Icon declared by MIDlet-1 inside the JAR, scaled for a 56pt cell.
UIImage *rt_game_icon(NSString *jarPath, const char *midlet);
NSString *rt_last_played_phrase(NSTimeInterval interval);
/// Scans <Documents>/games and returns sorted entries.
NSArray<RTGameEntry *> *rt_load_games(RTGameSortMode mode);
