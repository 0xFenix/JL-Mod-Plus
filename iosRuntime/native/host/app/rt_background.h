// Keeps the process alive while the app is in the background or the screen is
// locked, so games that hold a socket open do not lose their connection.
#ifndef RT_BACKGROUND_H
#define RT_BACKGROUND_H

/// Call once, before UIApplicationMain. Installs the silent audio session that
/// qualifies the app for background execution.
void rt_background_install(void);

#endif
