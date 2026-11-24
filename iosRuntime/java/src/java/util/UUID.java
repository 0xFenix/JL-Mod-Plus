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
package java.util;

/**
 * java.util.UUID — missing from miniJVM runtime.
 * Implements the subset used by J2ME games.
 */
public final class UUID implements java.io.Serializable, Comparable<UUID> {

    private final long mostSigBits;
    private final long leastSigBits;

    public UUID(long mostSigBits, long leastSigBits) {
        this.mostSigBits = mostSigBits;
        this.leastSigBits = leastSigBits;
    }

    public static UUID fromString(String name) {
        String[] parts = name.split("-");
        if (parts.length != 5) {
            throw new IllegalArgumentException("Invalid UUID string: " + name);
        }
        long msb = 0;
        long lsb = 0;
        msb = (Long.parseLong(parts[0], 16) << 32)
            | (Long.parseLong(parts[1], 16) << 16)
            |  Long.parseLong(parts[2], 16);
        lsb = (Long.parseLong(parts[3], 16) << 48)
            |  Long.parseLong(parts[4], 16);
        return new UUID(msb, lsb);
    }

    public static UUID randomUUID() {
        Random rng = new Random();
        byte[] data = new byte[16];
        for (int i = 0; i < 16; i++) {
            data[i] = (byte) rng.nextInt(256);
        }
        data[6] = (byte) ((data[6] & 0x0f) | 0x40); // version 4
        data[8] = (byte) ((data[8] & 0x3f) | 0x80); // variant 2
        long msb = 0;
        long lsb = 0;
        for (int i = 0; i < 8; i++) msb = (msb << 8) | (data[i] & 0xff);
        for (int i = 8; i < 16; i++) lsb = (lsb << 8) | (data[i] & 0xff);
        return new UUID(msb, lsb);
    }

    public long getMostSignificantBits() { return mostSigBits; }
    public long getLeastSignificantBits() { return leastSigBits; }

    public int version() { return (int) ((mostSigBits >> 12) & 0x0f); }
    public int variant() {
        long lsb = leastSigBits;
        if ((lsb >>> 63) == 0) return 0;
        if ((lsb >>> 62) == 2) return 2;
        return (int) (lsb >>> 61);
    }

    public String toString() {
        return digits(mostSigBits >> 32, 8) + "-"
             + digits(mostSigBits >> 16, 4) + "-"
             + digits(mostSigBits, 4) + "-"
             + digits(leastSigBits >> 48, 4) + "-"
             + digits(leastSigBits, 12);
    }

    private static String digits(long val, int digits) {
        long hi = 1L << (digits * 4);
        return Long.toHexString(hi | (val & (hi - 1))).substring(1);
    }

    public int hashCode() {
        long hilo = mostSigBits ^ leastSigBits;
        return (int) (hilo >> 32) ^ (int) hilo;
    }

    public boolean equals(Object obj) {
        if (!(obj instanceof UUID)) return false;
        UUID id = (UUID) obj;
        return mostSigBits == id.mostSigBits && leastSigBits == id.leastSigBits;
    }

    public int compareTo(UUID val) {
        int cmp = Long.compare(mostSigBits, val.mostSigBits);
        if (cmp != 0) return cmp;
        return Long.compare(leastSigBits, val.leastSigBits);
    }
}
