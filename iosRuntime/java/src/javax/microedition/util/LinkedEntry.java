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

/**
 * The linked list element.
 *
 * @param <E> what it contains
 */
public class LinkedEntry<E> {
	private LinkedEntry<E> prev;
	private LinkedEntry<E> next;

	private E element;

	/**
	 * Assign value to the element.
	 *
	 * @param element new value
	 */
	public void setElement(E element) {
		this.element = element;
	}

	/**
	 * @return the current value of the element
	 */
	public E getElement() {
		return element;
	}

	/**
	 * @return the element preceding this; or null if there is no such element
	 */
	public LinkedEntry<E> prevEntry() {
		return prev;
	}

	/**
	 * @return the element following the data; null if there is no such element
	 */
	public LinkedEntry<E> nextEntry() {
		return next;
	}

	/**
	 * Remove this item from the list.
	 * The adjacent elements are interconnected.
	 */
	public void remove() {
		if (prev != null) {
			prev.next = next;    // following the previous element = following this element
		}

		if (next != null) {
			next.prev = prev;    // preceding next element = preceding this element
		}

		prev = null;
		next = null;
	}

	/**
	 * Restore bidirectional links for this item.
	 * <p>
	 * That is, if there is someone in front of us, then we stand behind him;
	 * if someone is after us, then we are standing in front of him.
	 */
	private void updateLinks() {
		if (prev != null) {
			prev.next = this;
		}

		if (next != null) {
			next.prev = this;
		}
	}

	/**
	 * Insert this item before the specified one.
	 * It is assumed that the specified element is part of a list.
	 *
	 * @param entry
	 */
	public void insertBefore(LinkedEntry<E> entry) {
		remove();            // item cannot be in two places in the list at the same time

		prev = entry.prev;    // previous for the specified element - our previous one now
		next = entry;        // the specified element - our next one now

		updateLinks();        // bring these changes to our new neighbors
	}
}
