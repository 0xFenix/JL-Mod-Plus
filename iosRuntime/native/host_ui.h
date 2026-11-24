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

#ifdef __cplusplus
}
#endif

#endif
