/*
 * Derived from J2ME-Decade (iOS Edition) <https://github.com/darkrose00x-ux/j2me-ios>,
 * licensed under the Apache License, Version 2.0. That project states its J2ME API
 * layer is ported from J2ME-Loader <https://github.com/nikita36078/J2ME-Loader>,
 * whose javax.microedition sources are Copyright 2012 Kulikov Dmitriy,
 * 2017-2020 Nikita Shakarun, 2019-2023 Yury Kharchenko, Apache License 2.0.
 *
 * JL-Mod Plus modifications: removed the M3G (javax.microedition.m3g), MascotCapsule
 * micro3D, JBlend/Vodafone J3D, Bluetooth, Location and AMMS packages, which are
 * outside the iOS runtime scope.
 */
package javax.microedition.lcdui;

import java.util.ArrayList;

public class TextBox extends Screen {
    private String text;
    private int maxSize;
    private int constraints;

    public TextBox(String title, String text, int maxSize, int constraints) {
        setTitle(title);
        this.text = text != null ? text : "";
        this.maxSize = maxSize;
        this.constraints = constraints;
    }

    public String getString() { return text != null ? text : ""; }
    public void setString(String text) { this.text = text != null ? text : ""; }
    public int getMaxSize() { return maxSize; }
    public int setMaxSize(int maxSize) { this.maxSize = maxSize; return maxSize; }
    public int getConstraints() { return constraints; }
    public void setConstraints(int constraints) { this.constraints = constraints; }
    public int size() { return text != null ? text.length() : 0; }

    public void insert(String src, int position) {
        if (src == null) return;
        StringBuilder sb = new StringBuilder(text != null ? text : "");
        int pos = Math.max(0, Math.min(position, sb.length()));
        sb.insert(pos, src);
        this.text = sb.toString();
    }

    public void delete(int offset, int length) {
        if (text == null) return;
        StringBuilder sb = new StringBuilder(text);
        int start = Math.max(0, Math.min(offset, sb.length()));
        int end = Math.max(start, Math.min(start + length, sb.length()));
        if (start < end) {
            sb.delete(start, end);
            this.text = sb.toString();
        }
    }

    public int getCaretPosition() { return text != null ? text.length() : 0; }
    public void setInitialInputMode(String characterSubset) { }

    @Override
    protected void onCommandsChanged() {
        showNative();
    }

    /** Show native Decade TextBox UI */
    public void showNative() {
        NativeBridge.setTextBoxText(text != null ? text : "");
        NativeBridge.formBegin(getTitle() != null ? getTitle() : "", 3); // 3 = textbox
        NativeBridge.formAddTextField("", text != null ? text : "", maxSize, constraints);
        ArrayList<Command> cmds = getCommands();
        for (int i = 0; i < cmds.size(); i++) {
            Command c = cmds.get(i);
            NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
        }
        NativeBridge.formShow();
    }
}
