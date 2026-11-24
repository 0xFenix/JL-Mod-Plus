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
/*
 *  Copyright 2020 Yury Kharchenko
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package com.vodafone.v10.system.media;

import java.io.IOException;

import javax.microedition.lcdui.Canvas;
import javax.microedition.lcdui.Graphics;

public class MediaPlayer extends Canvas {
	public static final int ERROR = 65536;
	public static final int NO_DATA = 0;
	public static final int READY = 1;
	public static final int PLAYING = 2;
	public static final int PAUSED = 3;


	public MediaPlayer(byte[] data) {
	}

	public MediaPlayer(String url) throws IOException {
	}

	public int getHeight() {
		return 0;
	}

	public int getMediaHeight() {
		return 0;
	}

	public int getMediaWidth() {
		return 0;
	}

	public int getState() {
		return 0;
	}

	public int getWidth() {
		return 0;
	}

	protected void hideNotify() {
	}

	protected void paint(Graphics g) {
	}

	public void pause() {
	}

	public void play() {
	}

	public void play(boolean isRepeat) {
	}

	public void resume() {
	}

	public void setContentPos(int x, int y) {
	}

	public void setMediaData(byte[] data) {
	}

	public void setMediaData(String url) throws IOException {
	}

	public void setMediaPlayerListener(MediaPlayerListener listener) {
	}

	protected void showNotify() {
	}

	public void stop() {
	}
}