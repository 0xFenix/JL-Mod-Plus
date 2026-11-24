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

public abstract class Item {
    public static final int LAYOUT_DEFAULT = 0;
    public static final int LAYOUT_LEFT = 1;
    public static final int LAYOUT_RIGHT = 2;
    public static final int LAYOUT_CENTER = 3;
    public static final int PLAIN = 0;
    public static final int HYPERLINK = 1;
    public static final int BUTTON = 2;

    private String label;
    Form owner;
    private ArrayList<Command> commands = new ArrayList<Command>();
    private ItemCommandListener commandListener;
    private int layout = LAYOUT_DEFAULT;

    public void setLabel(String label) { this.label = label; }
    public String getLabel() { return label; }

    public void addCommand(Command cmd) { commands.add(cmd); }
    public void removeCommand(Command cmd) { commands.remove(cmd); }
    public void setItemCommandListener(ItemCommandListener l) { commandListener = l; }
    public void setDefaultCommand(Command cmd) { }

    public void setLayout(int layout) { this.layout = layout; }
    public int getLayout() { return layout; }
    public int getMinimumWidth() { return 0; }
    public int getMinimumHeight() { return 0; }
    public int getPreferredWidth() { return -1; }
    public int getPreferredHeight() { return -1; }
    public void setPreferredSize(int width, int height) { }

    public void notifyStateChanged() {
        if (owner != null) owner.notifyItemStateChanged(this);
    }

    /** Type ID for native bridge serialization */
    abstract int getItemType();
    String getItemLabel() { return label != null ? label : ""; }
    abstract String getItemText();
}
