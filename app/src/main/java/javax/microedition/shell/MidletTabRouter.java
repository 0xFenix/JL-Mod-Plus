/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package javax.microedition.shell;

import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.function.Predicate;

/**
 * Static thread-to-tab router for multi-MIDlet tabs sharing one process.
 *
 * <p>Guest and emulator statics (Display, MidletThread, timing) resolve the
 * owning tab from the calling thread: an exact MIDlet-thread match wins,
 * otherwise the tab whose guest-thread predicate accepts it. Host threads
 * fall back to the selected tab. The router owns no Android types so plain
 * JVM unit tests can cover the routing policy.
 */
public final class MidletTabRouter {
	/** Sentinel for "no tab". */
	public static final int NO_TAB = -1;

	private static final class Record {
		final Thread mainThread;
		final Predicate<Thread> ownsGuest;
		final Object runtime;

		Record(Thread mainThread, Predicate<Thread> ownsGuest, Object runtime) {
			this.mainThread = mainThread;
			this.ownsGuest = ownsGuest;
			this.runtime = runtime;
		}
	}

	private static final Map<Integer, Record> RECORDS = new HashMap<>();
	private static final Map<Object, Integer> GUEST_KEYS = new IdentityHashMap<>();
	private static volatile int selectedTabId = NO_TAB;

	private MidletTabRouter() {
	}

	/** Registers a tab runtime. Re-registration replaces the previous record. */
	public static synchronized void register(int tabId, Thread mainThread,
			Predicate<Thread> ownsGuest, Object runtime) {
		RECORDS.put(tabId, new Record(mainThread, ownsGuest, runtime));
	}

	/** Removes a tab runtime and its guest-key bindings. */
	public static synchronized void unregister(int tabId) {
		RECORDS.remove(tabId);
		GUEST_KEYS.entrySet().removeIf(entry -> entry.getValue() == tabId);
	}

	public static synchronized void clear() {
		RECORDS.clear();
		GUEST_KEYS.clear();
		selectedTabId = NO_TAB;
	}

	public static void setSelectedTab(int tabId) {
		selectedTabId = tabId;
	}

	public static int selectedTabId() {
		return selectedTabId;
	}

	public static synchronized Thread mainThreadForTab(int tabId) {
		Record record = RECORDS.get(tabId);
		return record == null ? null : record.mainThread;
	}

	public static synchronized Object runtimeForTab(int tabId) {
		Record record = RECORDS.get(tabId);
		return record == null ? null : record.runtime;
	}

	public static synchronized int tabCount() {
		return RECORDS.size();
	}

	/** Returns true when a live runtime is registered for the tab. */
	public static synchronized boolean isTabRegistered(int tabId) {
		return RECORDS.containsKey(tabId);
	}

	/** Returns a snapshot of the registered tab ids, for host rebuild after recreation. */
	public static synchronized java.util.Set<Integer> tabIds() {
		return new java.util.HashSet<>(RECORDS.keySet());
	}

	/** Binds an opaque guest key (for example a MIDlet instance) to a tab. */
	public static synchronized void bindGuestKey(int tabId, Object key) {
		if (key != null) {
			GUEST_KEYS.put(key, tabId);
		}
	}

	public static synchronized int tabForGuestKey(Object key) {
		Integer tabId = GUEST_KEYS.get(key);
		return tabId == null ? NO_TAB : tabId;
	}

	/**
	 * Resolves the owning tab for a thread: exact MIDlet-thread match first,
	 * then guest-thread predicates. Returns {@link #NO_TAB} when no tab owns
	 * the thread; callers fall back to the selected tab.
	 */
	public static synchronized int tabForThread(Thread thread) {
		if (thread != null) {
			for (Map.Entry<Integer, Record> entry : RECORDS.entrySet()) {
				if (entry.getValue().mainThread == thread) {
					return entry.getKey();
				}
			}
			for (Map.Entry<Integer, Record> entry : RECORDS.entrySet()) {
				Predicate<Thread> ownsGuest = entry.getValue().ownsGuest;
				if (ownsGuest != null && ownsGuest.test(thread)) {
					return entry.getKey();
				}
			}
		}
		return NO_TAB;
	}
}
