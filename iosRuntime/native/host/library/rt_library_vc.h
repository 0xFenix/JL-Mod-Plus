#ifndef RT_LIBRARY_VC_H
#define RT_LIBRARY_VC_H

#ifdef __cplusplus
extern "C" {
#endif

/// Build the game-library root controller (a UINavigationController whose root
/// is the library screen). Returns a +1 reference; the caller owns it.
void *rt_shell_root_controller(void);

/// Import a JAR handed over by another app (Files share sheet, "Open in").
/// Copies it into the library folder under a non-clashing name and posts
/// RTGamesChangedNotification so the visible library rescans. Returns 1 when
/// the file was imported. Safe to call from any thread; must be called with a
/// security-scoped URL already resolved by the caller.
int rt_import_jar_path(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* RT_LIBRARY_VC_H */
