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
 * Copyright 2012 Kulikov Dmitriy
 * Copyright 2017 Nikita Shakarun
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

package javax.microedition.util;

public class ArrayStack<E> {
	public static final int DELTA = 100;

	private Object[] data;
	private int index;

	public ArrayStack() {
		clear();
	}

	public synchronized void push(E value) {
		if (index >= data.length - 1) {
			Object[] temp = new Object[data.length + DELTA];
			System.arraycopy(data, 0, temp, 0, data.length);
			data = temp;
		}

		data[++index] = value;
	}

	public synchronized E pop() {
		if (index < 0) {
			return null;
		}

		//noinspection unchecked
		return (E) data[index--];
	}

	public synchronized void clear() {
		data = new Object[0];
		index = -1;
	}
}
