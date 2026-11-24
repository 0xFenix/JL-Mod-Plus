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
 * Player for MIDI via native AVMIDIPlayer + gs_instruments.sf2.
 * Analogous to J2ME-Loader's MidiPlayer wrapping MidiDriver.
 */
public class MidiPlayer extends BasePlayer {
    private long nativeHandle;
    private byte[] midiData;

    public MidiPlayer(byte[] data) {
        this.midiData = data;
    }

    protected void doRealize() throws MediaException {
        if (midiData != null) {
            nativeHandle = NativeBridge.audioCreateMidiPlayer(midiData);
            if (nativeHandle == 0) throw new MediaException("Failed to create MIDI player");
        }
    }

    protected void doStart() throws MediaException {
        if (nativeHandle != 0) NativeBridge.audioMidiStart(nativeHandle);
    }

    protected void doStop() throws MediaException {
        if (nativeHandle != 0) NativeBridge.audioMidiStop(nativeHandle);
    }

    protected void doClose() {
        if (nativeHandle != 0) {
            NativeBridge.audioMidiClose(nativeHandle);
            nativeHandle = 0;
        }
        midiData = null;
    }
}
