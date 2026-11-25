#ifndef RT_HOST_UI_H
#define RT_HOST_UI_H

#ifdef __cplusplus
extern "C" {
#endif

/// Present the runtime in a UIKit window: frames go to a game view and an
/// on-screen keypad posts MIDP key events through j2me_input. Blocks until the
/// app exits (UIApplicationMain).
int rt_run_ui(int argc, char **argv, const char *res_root, const char *save_root,
              const char *midlet_jar, int width, int height, int fps_limit);

/// Build a game screen for a specific JAR and configuration (+1 reference).
/// The library screen uses this to launch a title without touching globals.
void *rt_create_game_controller(const char *jar_path, int width, int height,
                                int fps_limit);

/// The shared game host (unretained; it lives as long as the process). Every
/// launched title becomes a tab in this one controller so games keep running
/// while another is focused.
void *rt_host_controller(void);

/// Number of sessions the host currently holds, running or finished.
int rt_host_running_count(void);

/// Closes every running game tab. The library uses it when the aggregate
/// "running games" row is swiped away.
void rt_host_close_all(void);

/// Launch a title as a new tab: adds it to the shared host and pushes that host
/// onto the library's navigation stack. `full_keyboard` selects the digit pad
/// and `turbo` makes a held fire key repeat.
void rt_present_game(const char *jar_path, int width, int height, int fps_limit,
                     const char *title, int full_keyboard, int turbo,
                     const char *keys);

#ifdef __cplusplus
}
#endif

#endif
