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
 * Copyright 2020 Nikita Shakarun
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.sprintpcs.media;

import javax.microedition.lcdui.Display;
import javax.microedition.media.MediaException;

public class Player {
	private static javax.microedition.media.Player player;
	private static int priority;

	public static void play(Clip clip, int repeat) {
		if (repeat < -1) {
			throw new IllegalArgumentException("Repeat must be -1 or greater");
		}
		if (clip.getPriority() < priority) {
			return;
		}
		if (player != null) {
			player.close();
		}
		if (repeat != -1) {
			repeat++;
		}
		player = clip.getPlayer();
		player.setLoopCount(repeat);
		Display.getDisplay(null).vibrate(clip.getVibration());
		try {
			player.start();
		} catch (MediaException e) {
			e.printStackTrace();
		}
	}

	public static void playBackground(Clip clip, int repeat) throws IllegalArgumentException {
		// stub — plays same as foreground
		play(clip, repeat);
	}

	public static void stop() {
		if (player != null) {
			player.close();
			player = null;
		}
	}
}
