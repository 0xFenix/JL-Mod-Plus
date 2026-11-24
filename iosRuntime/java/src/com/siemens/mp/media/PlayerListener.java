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
 *  Siemens API for MicroEmulator
 *  Copyright (C) 2003 Markus Heberling <markus@heberling.net>
 *
 *  It is licensed under the following two licenses as alternatives:
 *    1. GNU Lesser General Public License (the "LGPL") version 2.1 or any newer version
 *    2. Apache License (the "AL") Version 2.0
 *
 *  You may not use this file except in compliance with at least one of
 *  the above two licenses.
 *
 *  You may obtain a copy of the LGPL at
 *      http://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
 *
 *  You may obtain a copy of the AL at
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the LGPL or the AL for the specific language governing permissions and
 *  limitations.
 */
package com.siemens.mp.media;

public interface PlayerListener {
	public abstract void playerUpdate(Player player, String s, Object obj);

	public static final String STARTED = "started";
	public static final String STOPPED = "stopped";
	public static final String STOPPED_AT_TIME = "stoppedAtTime";
	public static final String END_OF_MEDIA = "endOfMedia";
	public static final String DURATION_UPDATED = "durationUpdated";
	public static final String DEVICE_UNAVAILABLE = "deviceUnavailable";
	public static final String DEVICE_AVAILABLE = "deviceAvailable";
	public static final String VOLUME_CHANGED = "volumeChanged";
	public static final String SIZE_CHANGED = "sizeChanged";
	public static final String ERROR = "error";
	public static final String CLOSED = "closed";
	public static final String RECORD_STARTED = "recordStarted";
	public static final String RECORD_STOPPED = "recordStopped";
	public static final String RECORD_ERROR = "recordError";
	public static final String BUFFERING_STARTED = "bufferingStarted";
	public static final String BUFFERING_STOPPED = "bufferingStopped";
}
