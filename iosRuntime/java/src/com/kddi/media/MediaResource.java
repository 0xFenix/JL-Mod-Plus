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
package com.kddi.media;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;

import javax.microedition.media.Manager;
import javax.microedition.media.MediaException;
import javax.microedition.media.Player;

public class MediaResource {
	private Player player;
	private String type;

	public Player _getPlayer() { return this.player; }

	public MediaResource(String url) {
		this.player = null;
		this.type = "devm39z";
		// Resource loading stub — MMFConverter not ported
	}

	public MediaResource(byte[] resource, String disposition) {
		this.player = null;
		this.type = disposition;
		// MMFConverter not ported — stub
	}

	public MediaPlayerBox[] getPlayer() { return new MediaPlayerBox[]{}; }
	public String getType() { return this.type; }

	public void dispose() {
		if (this.player != null) { this.player.close(); this.player = null; }
	}
}
