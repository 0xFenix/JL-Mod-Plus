//
// j2me_ui.m — Native UI bridge for J2ME LCDUI Forms/Lists/Alerts
//
// Java classes serialize their state via sequential native calls.
// Native side accumulates per-slot data and creates UIKit views on main thread.
// Supports multi-tab: each slot (0..31) maintains its own independent UI state.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "j2me_ui.h"
#include "j2me_input.h"
#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>
#include <string.h>
#include <pthread.h>

// ============================================================
// Per-Slot UI State
// ============================================================

#define MAX_SLOTS 32
#define MAX_FORM_ITEMS 64
#define MAX_COMMANDS 16

typedef struct {
    int type;           // 0=string, 1=textfield, 2=choice, 3=image, 4=spacer, 5=gauge
    char label[256];
    char text[1024];
    int intParam1;      // appearance/maxSize/choiceType
    int intParam2;      // constraints
} FormItem;

typedef struct {
    char label[128];
    int type;           // Command.SCREEN, BACK, OK, EXIT, etc.
    int priority;
    int id;             // sequential ID for event matching
} FormCommand;

typedef struct {
    char form_title[256];
    FormItem form_items[MAX_FORM_ITEMS];
    int form_item_count;
    FormCommand form_commands[MAX_COMMANDS];
    int form_command_count;
    int form_type;      // 0=form, 1=list, 2=alert, 3=textbox

    char list_items[MAX_FORM_ITEMS][256];
    int list_items_running[MAX_FORM_ITEMS];
    int list_item_count;
    int list_type;      // IMPLICIT=3, EXCLUSIVE=1, MULTIPLE=2

    char alert_text[1024];
    int alert_timeout;

    char textbox_text[2048];
    int active_action;  // J2ME_UI_ACTION_SHOW_CANVAS, SHOW_FORM, SHOW_LIST, etc.
} SlotUIState;

static SlotUIState g_slot_ui[MAX_SLOTS];
static pthread_mutex_t g_ui_mutex = PTHREAD_MUTEX_INITIALIZER;

static SlotUIState* get_slot_ui(int slot) {
    if (slot < 0 || slot >= MAX_SLOTS) slot = 0;
    return &g_slot_ui[slot];
}

static SlotUIState* get_focused_slot_ui(void) {
    int slot = jvm_bridge_get_focused_slot();
    return get_slot_ui(slot);
}

static j2me_ui_callback g_ui_callback = NULL;

void j2me_ui_set_callback(j2me_ui_callback callback) {
    g_ui_callback = callback;
}

int j2me_ui_get_slot_active_action(int slot) {
    pthread_mutex_lock(&g_ui_mutex);
    int action = J2ME_UI_ACTION_SHOW_CANVAS;
    if (slot >= 0 && slot < MAX_SLOTS) {
        action = g_slot_ui[slot].active_action;
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return action;
}

void j2me_ui_reset_slot(int slot) {
    pthread_mutex_lock(&g_ui_mutex);
    if (slot >= 0 && slot < MAX_SLOTS) {
        memset(&g_slot_ui[slot], 0, sizeof(SlotUIState));
        g_slot_ui[slot].alert_timeout = -2;
        g_slot_ui[slot].active_action = J2ME_UI_ACTION_SHOW_CANVAS;
    }
    pthread_mutex_unlock(&g_ui_mutex);
}

void j2me_ui_set_textbox_text(const char *text) {
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_focused_slot_ui();
    if (text) {
        strncpy(ui->textbox_text, text, sizeof(ui->textbox_text) - 1);
        ui->textbox_text[sizeof(ui->textbox_text) - 1] = '\0';
    } else {
        ui->textbox_text[0] = '\0';
    }
    pthread_mutex_unlock(&g_ui_mutex);
}

const char *j2me_ui_get_textbox_text(void) {
    return get_focused_slot_ui()->textbox_text;
}

// ============================================================
// Public getters for Swift side (read from focused slot)
// ============================================================

const char *j2me_ui_get_form_title(void) { return get_focused_slot_ui()->form_title; }
int j2me_ui_get_form_item_count(void) { return get_focused_slot_ui()->form_item_count; }
int j2me_ui_get_form_item_type(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_item_count) ? ui->form_items[index].type : -1;
}
const char *j2me_ui_get_form_item_label(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_item_count) ? ui->form_items[index].label : "";
}
const char *j2me_ui_get_form_item_text(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_item_count) ? ui->form_items[index].text : "";
}
int j2me_ui_get_form_item_param1(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_item_count) ? ui->form_items[index].intParam1 : 0;
}
int j2me_ui_get_form_item_param2(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_item_count) ? ui->form_items[index].intParam2 : 0;
}

int j2me_ui_get_command_count(void) { return get_focused_slot_ui()->form_command_count; }
const char *j2me_ui_get_command_label(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_command_count) ? ui->form_commands[index].label : "";
}
int j2me_ui_get_command_type(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_command_count) ? ui->form_commands[index].type : 0;
}
int j2me_ui_get_command_id(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->form_command_count) ? ui->form_commands[index].id : -1;
}

int j2me_ui_get_list_item_count(void) { return get_focused_slot_ui()->list_item_count; }
const char *j2me_ui_get_list_item(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    return (index >= 0 && index < ui->list_item_count) ? ui->list_items[index] : "";
}
int j2me_ui_get_list_type(void) { return get_focused_slot_ui()->list_type; }

const char *j2me_ui_get_alert_text(void) { return get_focused_slot_ui()->alert_text; }
int j2me_ui_get_alert_timeout(void) { return get_focused_slot_ui()->alert_timeout; }

int j2me_ui_is_list_item_running(int index) {
    SlotUIState *ui = get_focused_slot_ui();
    if (index >= 0 && index < ui->list_item_count) {
        return ui->list_items_running[index] != 0 ? 1 : 0;
    }
    return 0;
}

void j2me_ui_set_form_item_text(int index, const char *text) {
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_focused_slot_ui();
    if (index >= 0 && index < ui->form_item_count && text) {
        strncpy(ui->form_items[index].text, text, sizeof(ui->form_items[index].text) - 1);
        ui->form_items[index].text[sizeof(ui->form_items[index].text) - 1] = '\0';
    }
    pthread_mutex_unlock(&g_ui_mutex);
}

// ============================================================
// Native methods — called from Java to build UI
// ============================================================

static s32 n_formBegin(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jtitle = env->localvar_getRefer(runtime->localvar, 0);
    s32 type = env->localvar_getInt(runtime->localvar, 1);

    ui->form_item_count = 0;
    ui->form_command_count = 0;
    ui->list_item_count = 0;
    ui->form_type = type;

    if (jtitle) {
        Utf8String *ustr = utf8_create();
        env->jstring_2_utf8(jtitle, ustr, runtime);
        strncpy(ui->form_title, utf8_cstr(ustr), sizeof(ui->form_title) - 1);
        ui->form_title[sizeof(ui->form_title) - 1] = '\0';
        utf8_destroy(ustr);
    } else {
        ui->form_title[0] = '\0';
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddStringItem(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 1);
    s32 appearance = env->localvar_getInt(runtime->localvar, 2);

    if (ui->form_item_count >= MAX_FORM_ITEMS) {
        pthread_mutex_unlock(&g_ui_mutex);
        return RUNTIME_STATUS_NORMAL;
    }
    FormItem *item = &ui->form_items[ui->form_item_count++];
    item->type = 0; // string
    item->intParam1 = appearance;
    item->label[0] = '\0';
    item->text[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(item->label, utf8_cstr(u), sizeof(item->label) - 1);
        item->label[sizeof(item->label) - 1] = '\0';
        utf8_destroy(u);
    }
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(item->text, utf8_cstr(u), sizeof(item->text) - 1);
        item->text[sizeof(item->text) - 1] = '\0';
        if (ui->form_type == 3) { // TextBox: seed textbox_text
            strncpy(ui->textbox_text, utf8_cstr(u), sizeof(ui->textbox_text) - 1);
            ui->textbox_text[sizeof(ui->textbox_text) - 1] = '\0';
        }
        utf8_destroy(u);
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddTextField(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 1);
    s32 maxSize = env->localvar_getInt(runtime->localvar, 2);
    s32 constraints = env->localvar_getInt(runtime->localvar, 3);

    if (ui->form_item_count >= MAX_FORM_ITEMS) {
        pthread_mutex_unlock(&g_ui_mutex);
        return RUNTIME_STATUS_NORMAL;
    }
    FormItem *item = &ui->form_items[ui->form_item_count++];
    item->intParam1 = maxSize;
    item->intParam2 = constraints;
    item->label[0] = '\0';
    item->text[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(item->label, utf8_cstr(u), sizeof(item->label) - 1);
        item->label[sizeof(item->label) - 1] = '\0';
        utf8_destroy(u);
    }
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(item->text, utf8_cstr(u), sizeof(item->text) - 1);
        item->text[sizeof(item->text) - 1] = '\0';
        if (ui->form_type == 3) { // TextBox: seed textbox_text
            strncpy(ui->textbox_text, utf8_cstr(u), sizeof(ui->textbox_text) - 1);
            ui->textbox_text[sizeof(ui->textbox_text) - 1] = '\0';
        }
        utf8_destroy(u);
    }
    // ChoiceGroup passes Choice.EXCLUSIVE(1), MULTIPLE(2), or POPUP(4) with serialized multiline text
    if (ui->form_type == 0 && (maxSize == 1 || maxSize == 2 || maxSize == 4) && strchr(item->text, '\n') != NULL) {
        item->type = 2; // 2=choicegroup
    } else {
        item->type = 1; // 1=textfield
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddCommand(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    s32 cmdType = env->localvar_getInt(runtime->localvar, 1);
    s32 priority = env->localvar_getInt(runtime->localvar, 2);
    s32 cmdId = env->localvar_getInt(runtime->localvar, 3);

    if (ui->form_command_count >= MAX_COMMANDS) {
        pthread_mutex_unlock(&g_ui_mutex);
        return RUNTIME_STATUS_NORMAL;
    }
    FormCommand *cmd = &ui->form_commands[ui->form_command_count++];
    cmd->type = cmdType;
    cmd->priority = priority;
    cmd->id = cmdId;
    cmd->label[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(cmd->label, utf8_cstr(u), sizeof(cmd->label) - 1);
        cmd->label[sizeof(cmd->label) - 1] = '\0';
        utf8_destroy(u);
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formShow(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    int action = J2ME_UI_ACTION_SHOW_CANVAS;
    switch (ui->form_type) {
        case 0: action = J2ME_UI_ACTION_SHOW_FORM; break;
        case 1: action = J2ME_UI_ACTION_SHOW_LIST; break;
        case 2: action = J2ME_UI_ACTION_SHOW_ALERT; break;
        case 3: action = J2ME_UI_ACTION_SHOW_TEXTBOX; break;
        default: action = J2ME_UI_ACTION_SHOW_FORM; break;
    }
    ui->active_action = action;

    printf("[J2ME UI] formShow (slot %d, focused %d): type=%d title='%s' items=%d commands=%d\n",
           slot, jvm_bridge_get_focused_slot(), ui->form_type, ui->form_title, ui->form_item_count, ui->form_command_count);

    int is_focused = (slot == jvm_bridge_get_focused_slot());
    char title_copy[256];
    strncpy(title_copy, ui->form_title, sizeof(title_copy) - 1);
    title_copy[sizeof(title_copy) - 1] = '\0';
    pthread_mutex_unlock(&g_ui_mutex);

    if (is_focused && g_ui_callback) {
        g_ui_callback(action, title_copy);
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_showCanvas(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);
    ui->active_action = J2ME_UI_ACTION_SHOW_CANVAS;
    pthread_mutex_unlock(&g_ui_mutex);

    printf("[J2ME UI] showCanvas (slot %d, focused %d)\n", slot, jvm_bridge_get_focused_slot());
    if (slot == jvm_bridge_get_focused_slot() && g_ui_callback) {
        g_ui_callback(J2ME_UI_ACTION_SHOW_CANVAS, NULL);
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_listAddItem(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    s32 isRunning = env->localvar_getInt(runtime->localvar, 1);

    if (ui->list_item_count >= MAX_FORM_ITEMS) {
        pthread_mutex_unlock(&g_ui_mutex);
        return RUNTIME_STATUS_NORMAL;
    }
    ui->list_items[ui->list_item_count][0] = '\0';
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(ui->list_items[ui->list_item_count], utf8_cstr(u), 255);
        ui->list_items[ui->list_item_count][255] = '\0';
        utf8_destroy(u);
    }
    ui->list_items_running[ui->list_item_count] = (isRunning != 0) ? 1 : 0;
    ui->list_item_count++;
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_setListType(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    ui->list_type = env->localvar_getInt(runtime->localvar, 0);
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_setAlertText(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    s32 timeout = env->localvar_getInt(runtime->localvar, 1);
    ui->alert_timeout = timeout;
    ui->alert_text[0] = '\0';
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(ui->alert_text, utf8_cstr(u), sizeof(ui->alert_text) - 1);
        ui->alert_text[sizeof(ui->alert_text) - 1] = '\0';
        utf8_destroy(u);
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

// --- platformRequest: open URL in system browser ---

static s32 n_platformRequest(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    Instance *jurl = env->localvar_getRefer(runtime->localvar, 0);
    if (!jurl) return RUNTIME_STATUS_NORMAL;

    Utf8String *u = utf8_create();
    env->jstring_2_utf8(jurl, u, runtime);
    const char *urlStr = utf8_cstr(u);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:urlStr]];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });

    utf8_destroy(u);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_getTextBoxText(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jstr = env->jstring_create_cstr(ui->textbox_text, runtime);
    pthread_mutex_unlock(&g_ui_mutex);
    env->push_ref(runtime->stack, jstr);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_setTextBoxText(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(ui->textbox_text, utf8_cstr(u), sizeof(ui->textbox_text) - 1);
        ui->textbox_text[sizeof(ui->textbox_text) - 1] = '\0';
        utf8_destroy(u);
    } else {
        ui->textbox_text[0] = '\0';
    }
    pthread_mutex_unlock(&g_ui_mutex);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_getFormItemText(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    pthread_mutex_lock(&g_ui_mutex);
    SlotUIState *ui = get_slot_ui(slot);

    JniEnv *env = runtime->jnienv;
    s32 index = env->localvar_getInt(runtime->localvar, 0);
    Instance *jstr = NULL;
    if (index >= 0 && index < ui->form_item_count) {
        jstr = env->jstring_create_cstr(ui->form_items[index].text, runtime);
    }
    pthread_mutex_unlock(&g_ui_mutex);
    env->push_ref(runtime->stack, jstr);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method table
// ============================================================

#define CLS "javax/microedition/lcdui/NativeBridge"

static java_native_method j2me_ui_methods[] = {
    {CLS, "formBegin",        "(Ljava/lang/String;I)V",                          n_formBegin},
    {CLS, "formAddStringItem","(Ljava/lang/String;Ljava/lang/String;I)V",        n_formAddStringItem},
    {CLS, "formAddTextField", "(Ljava/lang/String;Ljava/lang/String;II)V",       n_formAddTextField},
    {CLS, "formAddCommand",   "(Ljava/lang/String;III)V",                        n_formAddCommand},
    {CLS, "formShow",         "()V",                                             n_formShow},
    {CLS, "showCanvas",       "()V",                                             n_showCanvas},
    {CLS, "listAddItem",      "(Ljava/lang/String;Z)V",                          n_listAddItem},
    {CLS, "setListType",      "(I)V",                                            n_setListType},
    {CLS, "setAlertText",     "(Ljava/lang/String;I)V",                          n_setAlertText},
    {CLS, "platformRequest",  "(Ljava/lang/String;)V",                           n_platformRequest},
    {CLS, "getTextBoxText",   "()Ljava/lang/String;",                            n_getTextBoxText},
    {CLS, "setTextBoxText",   "(Ljava/lang/String;)V",                           n_setTextBoxText},
    {CLS, "getFormItemText",  "(I)Ljava/lang/String;",                           n_getFormItemText},
};

#undef CLS

void j2me_ui_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_ui_methods,
                   sizeof(j2me_ui_methods) / sizeof(java_native_method));
    printf("[J2ME UI] Registered %lu native methods\n",
           sizeof(j2me_ui_methods) / sizeof(java_native_method));
}
