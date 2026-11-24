// Shared visual tokens for the UIKit host. The runtime screens are pixel art
// on black, so the chrome stays dark and quiet and a single warm accent marks
// the active control.
#ifndef HOST_THEME_H
#define HOST_THEME_H

#import <UIKit/UIKit.h>

static inline UIColor *rt_color_ink(void) {
    return [UIColor colorWithRed:0.039 green:0.043 blue:0.063 alpha:1.0];
}

static inline UIColor *rt_color_surface(void) {
    return [UIColor colorWithRed:0.078 green:0.086 blue:0.110 alpha:1.0];
}

static inline UIColor *rt_color_surface_raised(void) {
    return [UIColor colorWithRed:0.110 green:0.122 blue:0.157 alpha:1.0];
}

static inline UIColor *rt_color_hairline(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.08];
}

static inline UIColor *rt_color_accent(void) {
    return [UIColor colorWithRed:0.961 green:0.718 blue:0.357 alpha:1.0];
}

static inline UIColor *rt_color_text_primary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.95];
}

static inline UIColor *rt_color_text_secondary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.62];
}

static inline UIColor *rt_color_text_tertiary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.38];
}

static inline CGFloat rt_radius_card(void) {
    return 14.0;
}

static inline CGFloat rt_spacing(void) {
    return 8.0;
}

#endif
