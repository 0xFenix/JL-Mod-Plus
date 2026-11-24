#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include "garbage.h"
#include "j2me_render.h"
#include "j2me_input.h"
#include "j2me_ui.h"
#include "j2me_audio.h"
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>
#include <pthread.h>

#include <stdlib.h>
#include <strings.h>
#include <ctype.h>

typedef struct {
    MiniJVM *jvm;
    atomic_int stop_requested;
    atomic_int is_running;
    char jar_path[1024];
    char save_root[1024];
} SlotSessionNative;

static SlotSessionNative g_slots[JVM_BRIDGE_MAX_SLOTS];
static atomic_int g_focused_slot = 0;
static pthread_mutex_t g_slots_lock = PTHREAD_MUTEX_INITIALIZER;

int g_render_3d_scale = 1;

void jvm_bridge_set_focused_slot(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        atomic_store(&g_focused_slot, slot);
        printf("[JVM Bridge] Switched focused slot to %d\n", slot);
    }
}

int jvm_bridge_get_focused_slot(void) {
    return atomic_load(&g_focused_slot);
}

int jvm_bridge_get_jvm_slot(void *jvm_ptr) {
    if (!jvm_ptr) return 0;
    pthread_mutex_lock(&g_slots_lock);
    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        if (g_slots[i].jvm == jvm_ptr) {
            pthread_mutex_unlock(&g_slots_lock);
            return i;
        }
    }
    pthread_mutex_unlock(&g_slots_lock);
    return 0;
}

int jvm_bridge_init_slot(int slot, const char *res_root, const char *save_root, const char *midlet_jar,
                         int screen_width, int screen_height, int render_3d_scale,
                         int fps_limit) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) {
        printf("[JVM Bridge] ERROR: Invalid slot index %d\n", slot);
        return -1;
    }

    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[slot].jvm) {
        printf("[JVM Bridge] Slot %d already initialized\n", slot);
        pthread_mutex_unlock(&g_slots_lock);
        return -1;
    }

    char bootclasspath[1024];
    snprintf(bootclasspath, sizeof(bootclasspath), "%s/minijvm_rt.jar", res_root);

    char classpath[4096];
    snprintf(classpath, sizeof(classpath), "%s/j2me_api.jar:%s", res_root, midlet_jar);

    printf("[JVM Bridge] Slot %d initializing with classpath: %s\n", slot, classpath);

    MiniJVM *jvm = jvm_create();
    if (!jvm) {
        printf("[JVM Bridge] ERROR: jvm_create() failed for slot %d\n", slot);
        pthread_mutex_unlock(&g_slots_lock);
        return -2;
    }

    jvm->jdwp_enable = 0;
    jvm->jdwp_suspend_on_start = 0;
    jvm->max_heap_size = 128 * 1024 * 1024;
    jvm->garbage_collect_period_ms = 500;
    jvm->heap_overload_percent = 70;

    s32 ret = jvm_init(jvm, (c8 *)bootclasspath, (c8 *)classpath);
    if (ret) {
        printf("[JVM Bridge] ERROR: jvm_init() failed for slot %d (code %d)\n", slot, ret);
        jvm_destroy(jvm);
        pthread_mutex_unlock(&g_slots_lock);
        return -3;
    }

    // Register native methods for this slot's JVM instance
    j2me_render_reg_natives(jvm);
    j2me_input_reg_natives(jvm);
    j2me_ui_reg_natives(jvm);
    j2me_audio_reg_natives(jvm);

    // System properties
    sys_properties_set_c(jvm, "os.name", "iOS");
    sys_properties_set_c(jvm, "app.save.root", (c8 *)save_root);
    sys_properties_set_c(jvm, "microedition.platform", "Apple/iPhone");
    sys_properties_set_c(jvm, "microedition.encoding", "UTF-8");
    sys_properties_set_c(jvm, "microedition.locale", "en");
    sys_properties_set_c(jvm, "microedition.profiles", "MIDP-2.0");
    sys_properties_set_c(jvm, "microedition.configuration", "CLDC-1.1");

    char inst_str[16];
    snprintf(inst_str, sizeof(inst_str), "%d", slot + 1);
    sys_properties_set_c(jvm, "com.nokia.mid.cmdline.instance", inst_str);

    char sw[16], sh[16];
    snprintf(sw, sizeof(sw), "%d", screen_width);
    snprintf(sh, sizeof(sh), "%d", screen_height);
    sys_properties_set_c(jvm, "j2me.screen.width", sw);
    sys_properties_set_c(jvm, "j2me.screen.height", sh);

    g_render_3d_scale = render_3d_scale > 0 ? render_3d_scale : 1;

    if (fps_limit > 0) {
        char fl[8];
        snprintf(fl, sizeof(fl), "%d", fps_limit);
        sys_properties_set_c(jvm, "j2me.fps.limit", fl);
    }

    g_slots[slot].jvm = jvm;
    atomic_store(&g_slots[slot].stop_requested, 0);
    atomic_store(&g_slots[slot].is_running, 1);
    snprintf(g_slots[slot].jar_path, sizeof(g_slots[slot].jar_path), "%s", midlet_jar);
    snprintf(g_slots[slot].save_root, sizeof(g_slots[slot].save_root), "%s", save_root);

    pthread_mutex_unlock(&g_slots_lock);
    printf("[JVM Bridge] Slot %d JVM initialized successfully\n", slot);
    return 0;
}

int jvm_bridge_run_midlet_slot(int slot, const char *midlet_jar_path) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS || !g_slots[slot].jvm) {
        printf("[JVM Bridge] ERROR: Slot %d not ready to run\n", slot);
        return -1;
    }

    printf("[JVM Bridge] Slot %d executing MIDlet from: %s\n", slot, midlet_jar_path);

    ArrayList *java_para = arraylist_create(0);
    arraylist_push_back(java_para, (void *)midlet_jar_path);

    s32 ret = call_main(g_slots[slot].jvm, (c8 *)"javax/microedition/shell/MIDletRunner", java_para);
    arraylist_destroy(java_para);

    atomic_store(&g_slots[slot].is_running, 0);
    printf("[JVM Bridge] Slot %d MIDlet finished with code %d\n", slot, ret);
    return ret;
}

void jvm_bridge_destroy_slot(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;

    pthread_mutex_lock(&g_slots_lock);
    MiniJVM *jvm = g_slots[slot].jvm;
    if (jvm) {
        g_slots[slot].jvm = NULL;
        atomic_store(&g_slots[slot].is_running, 0);
        atomic_store(&g_slots[slot].stop_requested, 0);
        pthread_mutex_unlock(&g_slots_lock);

        printf("[JVM Bridge] Destroying slot %d JVM\n", slot);

        if (jvm->collector) {
            jvm->collector->exit_flag = 1;
        }
        thread_stop_all(jvm);
        jvm_destroy(jvm);
        return;
    }
    pthread_mutex_unlock(&g_slots_lock);
}

void jvm_bridge_destroy_all(void) {
    printf("[JVM Bridge] Destroying all slots\n");
    j2me_render_stop();

    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        jvm_bridge_destroy_slot(i);
    }

    j2me_input_reset();
    j2me_audio_stop_all();
    j2me_render_cleanup();
    atomic_store(&g_focused_slot, 0);
}

void jvm_bridge_request_stop_slot(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        atomic_store(&g_slots[slot].stop_requested, 1);
        printf("[JVM Bridge] Stop requested for slot %d\n", slot);
    }
}

void jvm_bridge_request_stop_all(void) {
    printf("[JVM Bridge] Requesting stop for ALL slots\n");
    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        atomic_store(&g_slots[i].stop_requested, 1);
        pthread_mutex_lock(&g_slots_lock);
        MiniJVM *jvm = g_slots[i].jvm;
        if (jvm && jvm->collector) {
            jvm->collector->exit_flag = 1;
        }
        pthread_mutex_unlock(&g_slots_lock);
    }
}

int jvm_bridge_is_slot_stop_requested(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        return atomic_load(&g_slots[slot].stop_requested);
    }
    return 0;
}

int jvm_bridge_is_slot_running(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        return atomic_load(&g_slots[slot].is_running);
    }
    return 0;
}

// Backward compatibility wrappers (slot 0)
int jvm_bridge_init(const char *res_root, const char *save_root, const char *midlet_jar,
                    int screen_width, int screen_height, int render_3d_scale,
                    int fps_limit) {
    return jvm_bridge_init_slot(0, res_root, save_root, midlet_jar, screen_width, screen_height, render_3d_scale, fps_limit);
}

int jvm_bridge_run_midlet(const char *midlet_jar_path) {
    return jvm_bridge_run_midlet_slot(0, midlet_jar_path);
}

void jvm_bridge_destroy(void) {
    jvm_bridge_destroy_all();
}

void jvm_bridge_set_save_root(const char *save_root) {
    int focused = jvm_bridge_get_focused_slot();
    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[focused].jvm && save_root) {
        sys_properties_set_c(g_slots[focused].jvm, "app.save.root", (c8 *)save_root);
        printf("[JVM Bridge] Switched app.save.root for slot %d to: %s\n", focused, save_root);
    }
    pthread_mutex_unlock(&g_slots_lock);
}

void jvm_bridge_request_stop(void) {
    jvm_bridge_request_stop_slot(jvm_bridge_get_focused_slot());
}

int jvm_bridge_is_stop_requested(void) {
    return jvm_bridge_is_slot_stop_requested(jvm_bridge_get_focused_slot());
}
