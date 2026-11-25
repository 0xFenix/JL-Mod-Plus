#import <UIKit/UIKit.h>

/// One card in the window switcher: a running game slot and how it looks.
@interface RTTabGridItem : NSObject
@property(nonatomic) int slot;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL focused;
@end

/// Grid of game windows, two columns with two rows visible and scrolling for
/// the rest. Selection and closing are delegated so this controller never
/// touches the JVM or the session list itself.
@interface RTTabGridController : UIViewController

/// Snapshot of the sessions, called on every reload.
@property(nonatomic, copy) NSArray<RTTabGridItem *> *(^itemsProvider)(void);
/// Latest frame of a slot as a UIImage, or nil while it has not painted yet.
@property(nonatomic, copy) UIImage *(^imageProvider)(int slot);
@property(nonatomic, copy) void (^onSelect)(int slot);
@property(nonatomic, copy) void (^onClose)(int slot);

- (void)reload;

@end
