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

public interface Choice {
    int EXCLUSIVE = 1;
    int MULTIPLE = 2;
    int IMPLICIT = 3;
    int POPUP = 4;
    int TEXT_WRAP_DEFAULT = 0;
    int TEXT_WRAP_ON = 1;
    int TEXT_WRAP_OFF = 2;

    int append(String stringPart, Image imagePart);
    void delete(int elementNum);
    void deleteAll();
    int getSelectedIndex();
    String getString(int elementNum);
    void insert(int elementNum, String stringPart, Image imagePart);
    boolean isSelected(int elementNum);
    void set(int elementNum, String stringPart, Image imagePart);
    void setSelectedIndex(int elementNum, boolean selected);
    int size();
    int getSelectedFlags(boolean[] selectedArray);
    void setSelectedFlags(boolean[] selectedArray);
    int getFitPolicy();
    void setFitPolicy(int fitPolicy);
    Font getFont(int elementNum);
    void setFont(int elementNum, Font font);
    Image getImage(int elementNum);
}
