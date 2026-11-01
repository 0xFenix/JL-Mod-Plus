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

		Tab(int id, String label) {
			this.id = id;
			this.label = label;
		}

		@Override
		public String toString() {
			return "Tab{id=" + id + ", label=" + label + '}';
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
		if (tabs.size() >= maxTabs) {
			return null;
		}
		Tab tab = new Tab(nextId++, label);
		tabs.add(tab);
		selectedId = tab.id;
		return tab;
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
