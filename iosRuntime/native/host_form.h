#ifndef HOST_FORM_H
#define HOST_FORM_H

#ifdef __cplusplus
extern "C" {
#endif

struct UIViewOpaque;

/// Install the j2me_ui callback and remember the view that hosts screen UI.
/// Must be called on the main thread before the MIDlet starts.
void rt_form_ui_attach(void *host_view);

/// Render the screen the Java layer last requested (Form, List, Alert, TextBox)
/// or hide the panel for Canvas. Main thread only.
void rt_form_ui_present(int action);

#ifdef __cplusplus
}
#endif

#endif /* HOST_FORM_H */
