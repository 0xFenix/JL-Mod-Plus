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
package javax.microedition.media;

import javax.microedition.lcdui.NativeBridge;

/**
 * Player for WAV/MP3 audio via native AVAudioPlayer.
 * Analogous to J2ME-Loader's MicroPlayer wrapping Android MediaPlayer.
 */
public class MicroPlayer extends BasePlayer {
    private long nativeHandle;
    private byte[] audioData;

    public MicroPlayer(byte[] data) {
        this.audioData = data;
    }

    protected void doRealize() throws MediaException {
        nativeHandle = NativeBridge.audioCreatePlayer(audioData);
        if (nativeHandle == 0) throw new MediaException("Failed to create audio player");
    }

    protected void doStart() throws MediaException {
        NativeBridge.audioStart(nativeHandle);
    }

    protected void doStop() throws MediaException {
        NativeBridge.audioStop(nativeHandle);
    }

    protected void doClose() {
        if (nativeHandle != 0) {
            NativeBridge.audioClose(nativeHandle);
            nativeHandle = 0;
        }
        audioData = null;
    }

    protected long doGetDuration() {
        return nativeHandle != 0 ? NativeBridge.audioGetDuration(nativeHandle) : TIME_UNKNOWN;
    }

    protected long doGetMediaTime() {
        return nativeHandle != 0 ? NativeBridge.audioGetTime(nativeHandle) : 0;
    }

    protected void doSetLevel(int level) {
        if (nativeHandle != 0) NativeBridge.audioSetVolume(nativeHandle, level / 100.0f);
    }

    public void setLoopCount(int count) {
        super.setLoopCount(count);
        if (nativeHandle != 0) NativeBridge.audioSetLoop(nativeHandle, count == -1 ? -1 : count - 1);
    }
}
