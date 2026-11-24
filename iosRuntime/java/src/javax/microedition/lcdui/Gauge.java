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

public class Gauge extends Item {
    public static final int INDEFINITE = -1;
    public static final int CONTINUOUS_IDLE = 0;
    public static final int INCREMENTAL_IDLE = 1;
    public static final int CONTINUOUS_RUNNING = 2;
    public static final int INCREMENTAL_UPDATING = 3;

    private int maxValue, value;
    private boolean interactive;

    public Gauge(String label, boolean interactive, int maxValue, int initialValue) {
        setLabel(label); this.interactive = interactive; this.maxValue = maxValue; this.value = initialValue;
    }
    public int getValue() { return value; }
    public void setValue(int value) { this.value = value; }
    public int getMaxValue() { return maxValue; }
    public void setMaxValue(int maxValue) { this.maxValue = maxValue; }
    public boolean isInteractive() { return interactive; }

    int getItemType() { return 5; }
    String getItemText() { return value + "/" + maxValue; }
}
