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
package com.nokia.mid.ui;
public class SoftNotificationImpl extends SoftNotification {
    private int id;
    SoftNotificationImpl() { }
    SoftNotificationImpl(int id) { this.id = id; }
    public int getId() { return id; }
    public void post() throws SoftNotificationException { }
    public void remove() throws SoftNotificationException { }
    public void setText(String text, String groupText) { }
    public void setImage(byte[] data) { }
    public void setSoftKeys(String left, String right) { }
    public void setSoftkeyLabels(String left, String right) { }
    public void setListener(SoftNotificationListener l) { }
}
