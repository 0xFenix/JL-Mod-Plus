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
 * Copyright 2021 ohayoyogi
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

package com.kddi.media;

public interface MediaPlayerInterface {

	void addMediaEventListener(MediaEventListener l);

	int getAttribute(int attr);

	int getPitch();

	MediaResource getResource();

	int getTempo();

	int getVolume();

	@Deprecated
	void hide();

	void pause();

	void play();

	void play(int count);

	void removeMediaEventListener(MediaEventListener l);

	void resume();

	void setAttribute(int attr, int value);

	void setPitch(int pitch);

	void setResource(MediaResource resource);

	void setTemp(int tempo);

	void setVolume(int volume);

	@Deprecated
	void show();

	void stop();

	void unsetResource(MediaResource resource);
}
