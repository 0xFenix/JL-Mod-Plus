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
package com.samsung.util;
import javax.microedition.media.*;
import java.io.*;
public class AudioClip {
    public static final int TYPE_MMF = 1;
    public static final int TYPE_MP3 = 2;
    public static final int TYPE_MIDI = 5;
    private Player player;
    public AudioClip(int type, String resname) {
        try {
            InputStream is = AudioClip.class.getResourceAsStream(resname);
            if (is == null && !resname.startsWith("/")) is = AudioClip.class.getResourceAsStream("/" + resname);
            if (is != null) { player = Manager.createPlayer(is, "audio/midi"); player.realize(); }
        } catch (Exception e) { System.out.println("AudioClip: " + e.getMessage()); }
    }
    public AudioClip(int type, byte[] data, int off, int len) {
        try { player = Manager.createPlayer(new ByteArrayInputStream(data, off, len), "audio/midi"); player.realize(); }
        catch (Exception e) { }
    }
    public void play(int loop, int vol) { try { if (player!=null) { player.setLoopCount(loop); player.start(); } } catch (Exception e) {} }
    public void pause() { try { if (player!=null) player.stop(); } catch (Exception e) {} }
    public void resume() { try { if (player!=null) player.start(); } catch (Exception e) {} }
    public void stop() { try { if (player!=null) player.stop(); } catch (Exception e) {} }
    public static boolean isSupported() { return true; }
}
