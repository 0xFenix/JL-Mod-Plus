#ifndef HOST_SHELL_H
#define HOST_SHELL_H

#ifdef __cplusplus
extern "C" {
#endif

/// Build the game-library root controller (a UINavigationController whose root
/// is the library screen). Returns a +1 reference; the caller owns it.
void *rt_shell_root_controller(void);

/// Directory holding installed game JARs (created on demand). Caller frees.
char *rt_games_directory(void);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SHELL_H */
