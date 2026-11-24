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

public class List extends Screen implements Choice {
    public static final int EXCLUSIVE = Choice.EXCLUSIVE;
    public static final int IMPLICIT = Choice.IMPLICIT;
    public static final int MULTIPLE = Choice.MULTIPLE;
    public static final Command SELECT_COMMAND = new Command("Select", Command.SCREEN, 0);

    private int listType;
    private ArrayList<String> strings = new ArrayList<String>();
    private ArrayList<Image> images = new ArrayList<Image>();
    private ArrayList<Boolean> selected = new ArrayList<Boolean>();
    private int selectedIndex = -1;
    private Command selectCommand = SELECT_COMMAND;

    public List(String title, int listType) {
        setTitle(title);
        this.listType = listType;
    }

    public List(String title, int listType, String[] stringElements, Image[] imageElements) {
        this(title, listType);
        if (stringElements != null) {
            for (int i = 0; i < stringElements.length; i++) {
                append(stringElements[i], imageElements != null && i < imageElements.length ? imageElements[i] : null);
            }
        }
    }

    public int append(String stringPart, Image imagePart) {
        strings.add(stringPart);
        images.add(imagePart);
        selected.add(Boolean.FALSE);
        if (selectedIndex < 0 && listType == EXCLUSIVE) selectedIndex = 0;
        if (isShown()) showNative();
        return strings.size() - 1;
    }

    public void delete(int elementNum) {
        strings.remove(elementNum); images.remove(elementNum); selected.remove(elementNum);
        if (isShown()) showNative();
    }
    public void deleteAll() {
        strings.clear(); images.clear(); selected.clear(); selectedIndex = -1;
        if (isShown()) showNative();
    }
    public int getSelectedIndex() {
        if (selectedIndex >= 0 && selectedIndex < strings.size()) {
            return selectedIndex;
        }
        return strings.isEmpty() ? -1 : 0;
    }
    public String getString(int elementNum) { return strings.get(elementNum); }
    public Image getImage(int elementNum) { return images.get(elementNum); }
    public void insert(int elementNum, String stringPart, Image imagePart) {
        strings.add(elementNum, stringPart); images.add(elementNum, imagePart); selected.add(elementNum, Boolean.FALSE);
        if (isShown()) showNative();
    }
    public boolean isSelected(int elementNum) { return selected.get(elementNum); }
    public void set(int elementNum, String stringPart, Image imagePart) {
        if (elementNum >= 0 && elementNum < strings.size()) {
            strings.set(elementNum, stringPart);
        }
        if (elementNum >= 0 && elementNum < images.size()) {
            images.set(elementNum, imagePart);
        }
        if (isShown()) showNative();
    }
    public void setSelectedIndex(int elementNum, boolean sel) {
        if (elementNum < 0 || elementNum >= selected.size()) return;
        if (listType == EXCLUSIVE) { for (int i = 0; i < selected.size(); i++) selected.set(i, Boolean.FALSE); }
        selected.set(elementNum, sel);
        if (sel) selectedIndex = elementNum;
    }
    public int size() { return strings.size(); }
    public int getSelectedFlags(boolean[] a) { for (int i = 0; i < a.length && i < selected.size(); i++) a[i] = selected.get(i); return selected.size(); }
    public void setSelectedFlags(boolean[] a) { for (int i = 0; i < a.length && i < selected.size(); i++) selected.set(i, a[i]); }
    public int getFitPolicy() { return 0; }
    public void setFitPolicy(int p) { }
    public Font getFont(int i) { return Font.getDefaultFont(); }
    public void setFont(int i, Font f) { }
    public void setSelectCommand(Command cmd) { selectCommand = cmd; }

    @Override
    protected void onCommandsChanged() {
        showNative();
    }

    public void showNative() {
        NativeBridge.formBegin(getTitle(), 1); // type 1 = list
        NativeBridge.setListType(listType);
        for (int i = 0; i < strings.size(); i++) {
            String s = strings.get(i);
            Image img = (i < images.size()) ? images.get(i) : null;
            boolean isRunning = (img != null && img.isRunningIcon);
            NativeBridge.listAddItem(s, isRunning);
        }
        ArrayList<Command> cmds = getCommands();
        for (int i = 0; i < cmds.size(); i++) {
            Command c = cmds.get(i);
            NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
        }
        NativeBridge.formShow();
    }

    public void handleListSelect(int index) {
        if (index >= 0 && index < strings.size()) {
            selectedIndex = index;
            if (listType == IMPLICIT && getCommandListener() != null && selectCommand != null) {
                getCommandListener().commandAction(selectCommand, this);
            }
        }
    }
}
