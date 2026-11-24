// The game surface: canvas scaling/touch mapping and the on-screen keypad.
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

/// Presents the latest J2ME framebuffer, letterboxed and nearest-neighbour.
@interface RTGameView : UIView
@property(nonatomic) CGImageRef currentImage;
@property(nonatomic) int canvasWidth;
@property(nonatomic) int canvasHeight;
@end

/// 3x3 MIDP keypad (soft keys, arrows, fire, * and #).
@interface RTKeypadView : UIView
@end
