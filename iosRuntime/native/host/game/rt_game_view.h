// The game surface: canvas scaling/touch mapping and the on-screen keypad.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

/// Presents the latest J2ME framebuffer, letterboxed and nearest-neighbour.
@interface RTGameView : UIView
@property(nonatomic) CGImageRef currentImage;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@end

/// MIDP keypad. Compact mode is the familiar 3x3 pad (soft keys, arrows,
/// fire, * and #); full mode adds the 12-key phone grid for games that need
/// digits.
@interface RTKeypadView : UIView
/// Switches layout immediately; the host resizes the container to match
/// `preferredHeight`.
- (void)setFullKeyboard:(BOOL)full;
@property(nonatomic, readonly) BOOL fullKeyboard;
/// Height the pad wants inside its container.
@property(nonatomic, readonly) CGFloat preferredHeight;
@end
