#ifndef JVM_BRIDGE_H
#define JVM_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#define JVM_BRIDGE_MAX_SLOTS 32

/// 3D supersampling scale factor requested by the host at slot init.
extern int g_render_3d_scale;

// ============================================================
// Multi-slot JVM lifecycle
// ============================================================

/// Initialize a specific slot session (slot 0..15).
int jvm_bridge_init_slot(int slot, const char *res_root, const char *save_root, const char *midlet_jar,
                         int screen_width, int screen_height, int render_3d_scale,
                         int fps_limit);

/// Run a MIDlet in a specific slot session via MIDletRunner.
int jvm_bridge_run_midlet_slot(int slot, const char *midlet_jar_path);

/// Destroy a specific slot session and free its resources.
void jvm_bridge_destroy_slot(int slot);

/// Destroy all active slot sessions.
void jvm_bridge_destroy_all(void);

// ============================================================
// Slot focus & identification
// ============================================================

/// Set the currently focused slot (which receives input and renders to main screen).
/// SOCKS5 proxy for one slot's JVM. Pass an empty host to disable. Safe to
/// call before init_slot; the settings are applied when the JVM is created.
void jvm_bridge_set_slot_proxy(int slot, const char *host, int port,
                               const char *user, const char *pass);

void jvm_bridge_set_focused_slot(int slot);

/// Get the currently focused slot index.
int jvm_bridge_get_focused_slot(void);

/// Determine which slot index owns the given MiniJVM pointer.
int jvm_bridge_get_jvm_slot(void *jvm_ptr);

// ============================================================
// Slot control & status
// ============================================================

/// Request graceful MIDlet stop for a slot.
void jvm_bridge_request_stop_slot(int slot);

/// Request graceful MIDlet stop for all slots.
void jvm_bridge_request_stop_all(void);

/// Check if stop has been requested for a slot.
int jvm_bridge_is_slot_stop_requested(int slot);

/// Check if a slot is currently active and running.
int jvm_bridge_is_slot_running(int slot);

// ============================================================
// Backward compatibility wrappers (default to slot 0)
// ============================================================

int jvm_bridge_init(const char *res_root, const char *save_root, const char *midlet_jar,
                    int screen_width, int screen_height, int render_3d_scale,
                    int fps_limit);

int jvm_bridge_run_midlet(const char *midlet_jar_path);

void jvm_bridge_destroy(void);

void jvm_bridge_set_save_root(const char *save_root);

void jvm_bridge_request_stop(void);

int jvm_bridge_is_stop_requested(void);

#ifdef __cplusplus
}
#endif

#endif /* JVM_BRIDGE_H */
