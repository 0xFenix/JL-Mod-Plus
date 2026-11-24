#ifndef RT_LIBRARY_VC_H
#define RT_LIBRARY_VC_H

#ifdef __cplusplus
extern "C" {
#endif

/// Build the game-library root controller (a UINavigationController whose root
/// is the library screen). Returns a +1 reference; the caller owns it.
void *rt_shell_root_controller(void);

#ifdef __cplusplus
}
#endif

#endif /* RT_LIBRARY_VC_H */
