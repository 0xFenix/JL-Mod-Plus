// The game surface: canvas scaling/touch mapping and the on-screen keypad.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

/// Presents the latest J2ME framebuffer, letterboxed and nearest-neighbour.
@interface RTGameView : UIView
@property(nonatomic) CGImageRef currentImage;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@end

/// MIDP keypad. Compact is 3x3 (soft keys, arrows, fire, * and #); the full
/// layout adds the ten digits for games that ask for them.
@interface RTKeypadView : UIView
/// Rebuilds the pad with the digit rows when YES. Ignored once `keyCodes` is
/// set, which is the per-game layout made in the editor (0 = empty slot).
@property(nonatomic) BOOL fullKeyboard;
/// Explicit per-game layout, three slots per row.
@property(nonatomic, copy) NSArray<NSNumber *> *keyCodes;
/// While YES, holding fire sends repeated press/release pairs (turbo).
@property(nonatomic) BOOL turboEnabled;
/// Height the current layout needs; the controller sizes its container to it.
@property(nonatomic, readonly) CGFloat preferredHeight;
@end
