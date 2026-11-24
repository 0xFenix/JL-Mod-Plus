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

public class StringItem extends Item {
    private String text;
    private int appearanceMode;

    public StringItem(String label, String text) {
        this(label, text, PLAIN);
    }

    public StringItem(String label, String text, int appearanceMode) {
        setLabel(label);
        this.text = text;
        this.appearanceMode = appearanceMode;
    }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }
    public int getAppearanceMode() { return appearanceMode; }
    public Font getFont() { return Font.getDefaultFont(); }
    public void setFont(Font font) { }

    int getItemType() { return 0; }
    String getItemText() { return text != null ? text : ""; }
}
