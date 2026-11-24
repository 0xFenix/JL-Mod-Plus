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

package javax.microedition.lcdui.event;



/**
 * The base class for all events.
 */
public abstract class Event implements Runnable {
	/**
	 * Event handling.
	 * This is where you need to perform the required actions.
	 */
	public abstract void process();

	/**
	 * Event recycling
	 * <p>
	 * If a pool of events is used, then the event must be reset
	 * and returned to the pool.
	 */
	public abstract void recycle();

	/**
	 * Handle the event and recycle it.
	 */
	@Override
	public void run() {
		try {
			process();
		} catch (Exception e) {
			System.out.println(getClass().getName() + " process: " + e.getMessage());
		} finally {
			leaveQueue();
			recycle();
		}
	}

	/**
	 * Called when an event has entered the queue.
	 * Here you can increase the count of such events in the queue.
	 */
	public abstract void enterQueue();

	/**
	 * Called when an event has left the queue.
	 * Here you can increase the count of such events in the queue.
	 */
	public abstract void leaveQueue();

	/**
	 * Check if this event can be queued
	 * immediately after some other event.
	 *
	 * @param event event after which we can put in queue
	 * @return true, if we agree to that
	 */
	public abstract boolean placeableAfter(Event event);
}