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
import javax.microedition.media.control.ToneControl;
import javax.microedition.media.tone.ToneSequence;

/**
 * Player for J2ME tone sequences. Converts tone byte[] to MIDI via ToneSequence,
 * then plays through AVMIDIPlayer.
 */
public class TonePlayer extends BasePlayer implements ToneControl {
    private byte[] sequence;
    private long nativeHandle;

    public TonePlayer() {
        addControl(ToneControl.class.getName(), this);
        addControl("ToneControl", this);
    }

    public void setSequence(byte[] seq) {
        if (state == STARTED) throw new IllegalStateException("Cannot set sequence while playing");
        this.sequence = seq;
    }

    protected void doStart() throws MediaException {
        if (sequence != null) {
            try {
                ToneSequence ts = new ToneSequence(sequence);
                ts.process();
                byte[] midiData = ts.getByteArray();
                nativeHandle = NativeBridge.audioCreateMidiPlayer(midiData);
                if (nativeHandle != 0) NativeBridge.audioMidiStart(nativeHandle);
            } catch (Exception e) {
                throw new MediaException("Tone sequence error: " + e.getMessage());
            }
        }
    }

    protected void doStop() throws MediaException {
        if (nativeHandle != 0) NativeBridge.audioMidiStop(nativeHandle);
    }

    protected void doClose() {
        if (nativeHandle != 0) {
            NativeBridge.audioMidiClose(nativeHandle);
            nativeHandle = 0;
        }
    }

    /**
     * Override deallocate to NOT stop playback immediately.
     * ToneManager.play() calls deallocate() right after start(),
     * but AVMIDIPlayer needs time to play the tone asynchronously.
     * In J2ME-Loader, MidiDriver keeps playing in a native thread
     * even after Java-side deallocate.
     */
    public void deallocate() {
        // Don't stop — let AVMIDIPlayer play to completion
        if (state == PREFETCHED) state = REALIZED;
    }
}
