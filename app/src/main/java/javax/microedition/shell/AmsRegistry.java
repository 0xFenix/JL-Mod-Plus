/*
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

package javax.microedition.shell;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Application-management registry for multi-MIDlet tabs.
 *
 * <p>One entry per running MIDlet tab in the same JVM/process. The registry is
 * UI-thread agnostic: every method is synchronized so host callbacks and the
 * Compose tab bar can share one instance. It owns no Android types so plain
 * JVM unit tests can cover the tab policy (default max 6 tabs, at least one
 * tab always present).
 */
public final class AmsRegistry {
	/** Default cap for concurrent MIDlet tabs in one runtime. */
	public static final int MAX_TABS = 6;

	/** Immutable snapshot of a single MIDlet tab. */
	public static final class Tab {
		public final int id;
		public final String label;
		/** Installed suite path owning this tab, or null when not yet launched. */
		public final String appPath;
		public final long expectedAppId;
		/** MIDlet main class, or null when the chooser has not resolved yet. */
		public final String mainClass;
		/** Human-readable suite title for per-tab naming, or null to use the host name. */
		public final String title;

		Tab(int id, String label) {
			this(id, label, null, 0L, null, null);
		}

		Tab(int id, String label, String appPath, long expectedAppId, String mainClass,
				String title) {
			this.id = id;
			this.label = label;
			this.appPath = appPath;
			this.expectedAppId = expectedAppId;
			this.mainClass = mainClass;
			this.title = title;
		}

		@Override
		public String toString() {
			return "Tab{id=" + id + ", label=" + label + ", appPath=" + appPath
					+ ", mainClass=" + mainClass + ", title=" + title + '}';
		}
	}

	private final int maxTabs;
	private final List<Tab> tabs = new ArrayList<>();
	private int nextId = 1;
	private int selectedId = -1;

	public AmsRegistry() {
		this(MAX_TABS);
	}

	public AmsRegistry(int maxTabs) {
		this.maxTabs = Math.max(1, maxTabs);
	}

	/**
	 * Adds a tab and selects it. Returns null when the tab cap is reached.
	 */
	public synchronized Tab addTab(String label) {
		return addTab(label, null, 0L, null);
	}

	/**
	 * Adds a tab carrying its suite identity and selects it.
	 * Returns null when the tab cap is reached.
	 */
	public synchronized Tab addTab(String label, String appPath, long expectedAppId,
			String mainClass) {
		return addTab(label, appPath, expectedAppId, mainClass, null);
	}

	/**
	 * Adds a tab carrying its suite identity and display title, and selects it.
	 * Returns null when the tab cap is reached.
	 */
	public synchronized Tab addTab(String label, String appPath, long expectedAppId,
			String mainClass, String title) {
		if (tabs.size() >= maxTabs) {
			return null;
		}
		Tab tab = new Tab(nextId++, label, appPath, expectedAppId, mainClass, title);
		tabs.add(tab);
		selectedId = tab.id;
		return tab;
	}

	/**
	 * Records the suite identity of a launched tab, preserving its position
	 * and display title. Returns false for unknown ids.
	 */
	public synchronized boolean setTabSuite(int id, String appPath, long expectedAppId,
			String mainClass) {
		for (int i = 0; i < tabs.size(); i++) {
			if (tabs.get(i).id == id) {
				return setTabSuite(id, appPath, expectedAppId, mainClass,
						tabs.get(i).title);
			}
		}
		return false;
	}

	/**
	 * Records the suite identity and display title of a launched tab,
	 * preserving its position. Returns false for unknown ids.
	 */
	public synchronized boolean setTabSuite(int id, String appPath, long expectedAppId,
			String mainClass, String title) {
		for (int i = 0; i < tabs.size(); i++) {
			if (tabs.get(i).id == id) {
				tabs.set(i, new Tab(id, tabs.get(i).label, appPath, expectedAppId,
						mainClass, title));
				return true;
			}
		}
		return false;
	}

	/** Selects an existing tab. Returns false for unknown ids. */
	public synchronized boolean selectTab(int id) {
		for (Tab tab : tabs) {
			if (tab.id == id) {
				selectedId = id;
				return true;
			}
		}
		return false;
	}

	/**
	 * Closes a tab. The last remaining tab cannot be closed because the
	 * runtime always hosts at least one MIDlet entry. Closing the selected
	 * tab selects its nearest neighbour. Returns false for unknown ids or
	 * when refusing to close the final tab.
	 */
	public synchronized boolean closeTab(int id) {
		if (tabs.size() <= 1) {
			return false;
		}
		int index = -1;
		for (int i = 0; i < tabs.size(); i++) {
			if (tabs.get(i).id == id) {
				index = i;
				break;
			}
		}
		if (index < 0) {
			return false;
		}
		tabs.remove(index);
		if (selectedId == id) {
			selectedId = tabs.get(Math.min(index, tabs.size() - 1)).id;
		}
		return true;
	}

	public synchronized List<Tab> snapshot() {
		return Collections.unmodifiableList(new ArrayList<>(tabs));
	}

	public synchronized int selectedId() {
		return selectedId;
	}

	public synchronized int size() {
		return tabs.size();
	}

	public synchronized boolean isFull() {
		return tabs.size() >= maxTabs;
	}
}
