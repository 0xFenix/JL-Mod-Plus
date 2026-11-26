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

package io.github.h3nb.jlmodplus.net;

import java.util.HashMap;
import java.util.Map;

import javax.microedition.shell.MidletTabRouter;

/**
 * Resolves the proxy assigned to the calling guest tab.
 *
 * <p>A tab id alone cannot identify the installed app or its launch slot, so
 * MicroLoader (or whatever creates the tab) must call {@link #bindTab} once
 * per tab. Until then the tab is unbound and connects directly.
 */
public final class ProxyRouting {
	public static final class Socks5Config {
		public final String host;
		public final int port;
		public final String user;
		public final String pass;

		Socks5Config(ProxyStore.Entry entry) {
			this.host = entry.host;
			this.port = entry.port;
			this.user = entry.user;
			this.pass = entry.pass;
		}
	}

	private static final class Binding {
		final String storageKey;
		final int slotIndex;

		Binding(String storageKey, int slotIndex) {
			this.storageKey = storageKey;
			this.slotIndex = slotIndex;
		}
	}

	private static final Map<Integer, Binding> BINDINGS = new HashMap<>();

	private ProxyRouting() {
	}

	/** Binds a tab to an installed app's launch slot. Call at tab creation. */
	public static synchronized void bindTab(int tabId, String storageKey, int slotIndex) {
		if (tabId == MidletTabRouter.NO_TAB || storageKey == null) {
			return;
		}
		BINDINGS.put(tabId, new Binding(storageKey, slotIndex));
	}

	/** Drops a closed tab's binding so a reused tab id cannot inherit its proxy. */
	public static synchronized void unbindTab(int tabId) {
		BINDINGS.remove(tabId);
	}

	/** Returns the proxy for the calling tab, or null when it should connect directly. */
	public static Socks5Config currentForThread() {
		int tabId = MidletTabRouter.tabForThread(Thread.currentThread());
		if (tabId == MidletTabRouter.NO_TAB) {
			tabId = MidletTabRouter.selectedTabId();
		}
		Binding binding;
		synchronized (ProxyRouting.class) {
			binding = BINDINGS.get(tabId);
		}
		if (binding == null) {
			// Check the binding first: unbound threads must never touch storage,
			// which keeps plain unit tests and direct-only tabs Android-free.
			return null;
		}
		ProxyStore store = ProxyStore.forApp();
		String proxyId = store.proxyIdForTab(binding.storageKey, binding.slotIndex);
		if (proxyId == null) {
			return null;
		}
		ProxyStore.Entry entry = store.find(proxyId);
		return entry == null ? null : new Socks5Config(entry);
	}
}
