#ifndef J2ME_UI_H
#define J2ME_UI_H

#include <stdbool.h>
#include "jvm.h"

#ifdef __cplusplus
extern "C" {
#endif

// UI event types (added to input queue alongside touch/key events)
#define J2ME_UI_COMMAND_ACTION   10
#define J2ME_UI_LIST_SELECT      11
#define J2ME_UI_ALERT_DISMISSED  12
#define J2ME_UI_LIST_SET_INDEX   13

/// Register UI-related native methods with the JVM.
void j2me_ui_reg_natives(MiniJVM *jvm);

/// Callback for creating/showing native iOS views.
/// Called from JVM thread — implementations must dispatch to main thread.
typedef void (*j2me_ui_callback)(int action, const char *data);

/// Set the UI callback.
void j2me_ui_set_callback(j2me_ui_callback callback);

// UI actions for the callback
#define J2ME_UI_ACTION_SHOW_CANVAS    1
#define J2ME_UI_ACTION_SHOW_FORM      2
#define J2ME_UI_ACTION_SHOW_LIST      3
#define J2ME_UI_ACTION_SHOW_ALERT     4
#define J2ME_UI_ACTION_SHOW_TEXTBOX   5

// Set and get the active TextBox text buffer
void j2me_ui_set_textbox_text(const char *text);
const char *j2me_ui_get_textbox_text(void);

// Update Form item text from Swift
void j2me_ui_set_form_item_text(int index, const char *text);

// Form and UI item getters for Swift
int j2me_ui_get_slot_active_action(int slot);
void j2me_ui_reset_slot(int slot);
const char *j2me_ui_get_form_title(void);
int j2me_ui_get_form_item_count(void);
int j2me_ui_get_form_item_type(int index);
const char *j2me_ui_get_form_item_label(int index);
const char *j2me_ui_get_form_item_text(int index);
int j2me_ui_get_form_item_param1(int index);
int j2me_ui_get_form_item_param2(int index);
int j2me_ui_get_command_count(void);
const char *j2me_ui_get_command_label(int index);
int j2me_ui_get_command_type(int index);
int j2me_ui_get_command_id(int index);
int j2me_ui_get_list_item_count(void);
const char *j2me_ui_get_list_item(int index);
int j2me_ui_is_list_item_running(int index);
int j2me_ui_get_list_type(void);
const char *j2me_ui_get_alert_text(void);
int j2me_ui_get_alert_timeout(void);

#ifdef __cplusplus
}
#endif

#endif /* J2ME_UI_H */
