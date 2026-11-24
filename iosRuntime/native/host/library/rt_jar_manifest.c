// Minimal JAR metadata reader for the game library. The engine already links
// miniz, so this reuses it instead of adding a second zip implementation.

#include "rt_jar_manifest.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "miniz.h"

#define MANIFEST_NAME "META-INF/MANIFEST.MF"
#define MANIFEST_MAX 65536

// Copies the value of `key` from a JAR manifest into `dst`, trimming the
// leading space and trailing CR of the value line. Manifest continuation
// lines (leading space) are rare for the keys used here and stay unsupported.
static void copy_manifest_value(const char *manifest, const char *key,
                                char *dst, size_t dst_len) {
    if (!dst || dst_len == 0) {
        return;
    }
    dst[0] = '\0';
    size_t key_len = strlen(key);
    const char *line = manifest;
    while (line && *line) {
        if (strncmp(line, key, key_len) == 0) {
            const char *value = line + key_len;
            while (*value == ' ') {
                value++;
            }
            const char *end = value;
            while (*end && *end != '\r' && *end != '\n') {
                end++;
            }
            size_t len = (size_t) (end - value);
            if (len >= dst_len) {
                len = dst_len - 1;
            }
            memcpy(dst, value, len);
            dst[len] = '\0';
            return;
        }
        line = strchr(line, '\n');
        if (line) {
            line++;
        }
    }
}

int rt_jar_read_manifest(const char *jar_path,
                         char *name, size_t name_len,
                         char *midlet, size_t midlet_len) {
    if (!jar_path) {
        return 0;
    }
    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_file(&zip, jar_path, 0)) {
        return 0;
    }
    int found = 0;
    int index = mz_zip_reader_locate_file(&zip, MANIFEST_NAME, NULL, 0);
    if (index >= 0) {
        char *buf = (char *) malloc(MANIFEST_MAX);
        if (buf) {
            if (mz_zip_reader_extract_to_mem(&zip, (mz_uint) index, buf,
                                             MANIFEST_MAX - 1, 0)) {
                buf[MANIFEST_MAX - 1] = '\0';
                copy_manifest_value(buf, "MIDlet-Name:", name, name_len);
                copy_manifest_value(buf, "MIDlet-1:", midlet, midlet_len);
                found = 1;
            }
            free(buf);
        }
    }
    mz_zip_reader_end(&zip);
    return found;
}

const char *rt_jar_midlet_class(const char *midlet) {
    if (!midlet) {
        return NULL;
    }
    const char *last = strrchr(midlet, ',');
    if (!last) {
        return NULL;
    }
    last++;
    while (*last == ' ') {
        last++;
    }
    return *last ? last : NULL;
}

int rt_jar_midlet_icon(const char *midlet, char *icon, size_t icon_len) {
    if (!icon || icon_len == 0) {
        return 0;
    }
    icon[0] = '\0';
    if (!midlet) {
        return 0;
    }
    const char *start = strchr(midlet, ',');
    if (!start) {
        return 0;
    }
    start++;
    const char *end = strchr(start, ',');
    if (!end) {
        return 0;
    }
    while (*start == ' ') {
        start++;
    }
    while (end > start && end[-1] == ' ') {
        end--;
    }
    if (end <= start) {
        return 0;
    }
    // Jar entries never carry the leading "/" that MIDlet manifests use.
    while (start < end && *start == '/') {
        start++;
    }
    size_t len = (size_t) (end - start);
    if (len >= icon_len) {
        len = icon_len - 1;
    }
    memcpy(icon, start, len);
    icon[len] = '\0';
    return icon[0] ? 1 : 0;
}

unsigned char *rt_jar_extract_entry(const char *jar_path, const char *entry,
                                    size_t *out_len) {
    if (out_len) {
        *out_len = 0;
    }
    if (!jar_path || !entry || !entry[0]) {
        return NULL;
    }
    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_file(&zip, jar_path, 0)) {
        return NULL;
    }
    unsigned char *result = NULL;
    int index = mz_zip_reader_locate_file(&zip, entry, NULL, 0);
    if (index >= 0) {
        mz_zip_archive_file_stat stat;
        if (mz_zip_reader_file_stat(&zip, (mz_uint) index, &stat) &&
            stat.m_uncomp_size > 0 && stat.m_uncomp_size < (mz_uint64) (8 * 1024 * 1024)) {
            size_t size = (size_t) stat.m_uncomp_size;
            unsigned char *buf = (unsigned char *) malloc(size);
            if (buf && mz_zip_reader_extract_to_mem(&zip, (mz_uint) index, buf, size, 0)) {
                result = buf;
                if (out_len) {
                    *out_len = size;
                }
            } else {
                free(buf);
            }
        }
    }
    mz_zip_reader_end(&zip);
    return result;
}
