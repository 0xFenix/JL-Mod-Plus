#ifndef HOST_JAR_H
#define HOST_JAR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Read display metadata from a MIDlet JAR without starting a JVM.
/// Copies the MIDlet-Name attribute into `name` and the MIDlet-1 entry (the
/// "name, icon, class" triple) into `midlet`. Either buffer may be NULL.
/// Returns 1 when a manifest was read, 0 otherwise.
int rt_jar_read_manifest(const char *jar_path,
                         char *name, size_t name_len,
                         char *midlet, size_t midlet_len);

/// Extract the class name from a MIDlet-1 style value ("Name, /icon.png, pkg.Class").
/// Returns the offset into `midlet` where the class name starts, or 0 if the
/// value has no comma-separated class field.
const char *rt_jar_midlet_class(const char *midlet);

/// Copy the icon path from a MIDlet-1 style value into `icon`, dropping the
/// leading "/" so it can be passed to rt_jar_extract_entry.
/// Returns 1 when an icon field was found.
int rt_jar_midlet_icon(const char *midlet, char *icon, size_t icon_len);

/// Read one uncompressed entry out of a JAR. Returns a malloc'ed buffer (caller
/// frees) and sets `out_len`, or NULL when the entry is absent.
unsigned char *rt_jar_extract_entry(const char *jar_path, const char *entry,
                                    size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* HOST_JAR_H */
