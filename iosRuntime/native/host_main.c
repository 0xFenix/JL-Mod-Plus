// Headless host for the J2ME runtime: boots one MIDlet through jvm_bridge,
// receives rendered frames through the flush callback, writes periodic PNG
// snapshots and reports FPS. No UIKit window is created; Canvas-only games
// render fine, native form UI is a later pass.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

#include "jvm_bridge.h"
#include "j2me_render.h"
#include "host_ui.h"

// The reference runtime hooks a patched collector (its vendored garbage.c) so
// native image memory counts toward heap pressure. Upstream miniJVM has no such
// counter, so the hook is satisfied here as a plain no-op: native image memory
// is not counted against the GC budget.
s64 g_native_extra_heap = 0;

static int snapshot_dir_set = 0;
static char snapshot_dir[1024];
static int frames = 0;
static double started = 0;

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double) ts.tv_sec + (double) ts.tv_nsec / 1e9;
}

static void write_png(void *image, int width, int height, const char *path) {
    CGImageRef cg = (CGImageRef) image;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
            NULL, (const UInt8 *) path, (CFIndex) strlen(path), false);
    if (!url) return;
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    if (dest) {
        CGImageDestinationAddImage(dest, cg, NULL);
        CGImageDestinationFinalize(dest);
        CFRelease(dest);
    }
    CFRelease(url);
}

static void on_flush(void *image, int width, int height) {
    if (!image) return;
    frames++;
    if (frames % 60 == 0 && snapshot_dir_set) {
        double elapsed = now_seconds() - started;
        double fps = elapsed > 0 ? (double) frames / elapsed : 0;
        char path[1200];
        snprintf(path, sizeof(path), "%s/frame_%06d.png", snapshot_dir, frames);
        write_png(image, width, height, path);
        printf("[RT] frames=%d %.1fs fps=%.1f %dx%d -> %s\n",
               frames, elapsed, fps, width, height, path);
        fflush(stdout);
    }
    CFRelease((CFTypeRef) image);
}

int main(int argc, char **argv) {
    const char *res_root = getenv("RT_RES_ROOT");
    const char *save_root = getenv("RT_SAVE_ROOT");
    const char *midlet_jar = getenv("RT_MIDLET_JAR") ? getenv("RT_MIDLET_JAR")
                                                    : (argc > 1 ? argv[1] : NULL);
    const char *snap = getenv("RT_SNAPSHOT_DIR");
    int width = getenv("RT_WIDTH") ? atoi(getenv("RT_WIDTH")) : 240;
    int height = getenv("RT_HEIGHT") ? atoi(getenv("RT_HEIGHT")) : 320;
    int fps_limit = getenv("RT_FPS_LIMIT") ? atoi(getenv("RT_FPS_LIMIT")) : 0;

    if (!res_root || !save_root) {
        // Launched from springboard there are no env vars: fall back to the
        // bundle's jars and the app container, so the library screen works.
        static char res_buf[4096];
        static char save_buf[4096];
        if (!res_root) {
            strncpy(res_buf, argv[0], sizeof(res_buf) - 1);
            char *slash = strrchr(res_buf, '/');
            if (slash) *slash = '\0';
            strncat(res_buf, "/jars", sizeof(res_buf) - strlen(res_buf) - 1);
            res_root = res_buf;
        }
        if (!save_root) {
            const char *home = getenv("HOME");
            snprintf(save_buf, sizeof(save_buf), "%s/Documents/save", home ? home : ".");
            save_root = save_buf;
        }
    }
    if (!res_root || !save_root) {
        printf("[RT] cannot resolve resource/save roots\n");
        return 2;
    }
    if (snap) {
        strncpy(snapshot_dir, snap, sizeof(snapshot_dir) - 1);
        snapshot_dir_set = 1;
    }
    printf("[RT] res_root=%s\n[RT] save_root=%s\n[RT] jar=%s screen=%dx%d fps_limit=%d\n",
           res_root, save_root, midlet_jar ? midlet_jar : "(library)", width, height, fps_limit);

    // RT_HEADLESS=1 keeps the snapshot/FPS harness used for automated runs;
    // the default is a window with on-screen controls, which is the only way
    // gameplay frame rates can be judged.
    const char *headless = getenv("RT_HEADLESS");
    if ((!headless || strcmp(headless, "1") != 0)) {
        return rt_run_ui(argc, argv, res_root, save_root, midlet_jar, width, height, fps_limit);
    }
    if (!midlet_jar) {
        printf("[RT] headless mode needs RT_MIDLET_JAR\n");
        return 2;
    }

    j2me_render_set_flush_callback(on_flush);
    started = now_seconds();

    if (jvm_bridge_init_slot(0, res_root, save_root, midlet_jar, width, height, 1, fps_limit) != 0) {
        printf("[RT] jvm_bridge_init_slot failed\n");
        return 3;
    }
    jvm_bridge_set_focused_slot(0);
    printf("[RT] jvm initialized, running midlet\n");
    fflush(stdout);

    jvm_bridge_run_midlet_slot(0, midlet_jar);
    printf("[RT] midlet run returned, frames=%d\n", frames);
    fflush(stdout);

    j2me_render_stop();
    j2me_render_cleanup();
    jvm_bridge_destroy_slot(0);
    printf("[RT] done\n");
    return 0;
}
