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

public class ImageItem extends Item {
    public static final int LAYOUT_DEFAULT = 0;
    public static final int LAYOUT_LEFT = 1;
    public static final int LAYOUT_RIGHT = 2;
    public static final int LAYOUT_CENTER = 3;

    private Image image;
    private String altText;
    private int appearanceMode;

    public ImageItem(String label, Image img, int layout, String altText) {
        setLabel(label); this.image = img; setLayout(layout); this.altText = altText;
    }
    public ImageItem(String label, Image img, int layout, String altText, int appearanceMode) {
        this(label, img, layout, altText); this.appearanceMode = appearanceMode;
    }

    public Image getImage() { return image; }
    public void setImage(Image img) { this.image = img; }
    public String getAltText() { return altText; }
    public void setAltText(String text) { this.altText = text; }
    public int getAppearanceMode() { return appearanceMode; }

    int getItemType() { return 3; }
    String getItemText() { return altText != null ? altText : ""; }
}
