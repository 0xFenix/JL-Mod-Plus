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

import android.content.Context;
import android.content.SharedPreferences;

import org.microemu.cldc.net.Socks5Tunnel;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.Socket;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import javax.microedition.util.ContextHolder;

/**
 * Saved SOCKS5 proxies and per-launch-slot assignments.
 *
 * <p>Proxy ids are {@code host:port:user}. Slot lists are stored per installed
 * app (its VFS storage key) as an ordered list of proxy ids; slot 0 is the
 * first tab launched for that app. A missing slot is intentionally "direct"
 * rather than falling back to an app default.
 */
public final class ProxyStore {
	private static final String PREFS_NAME = "proxy_store";
	private static final String KEY_ENTRIES = "entries";
	private static final String SLOT_PREFIX = "proxy_slots_";

	public static final class Entry {
		public final String id;
		public final String host;
		public final int port;
		public final String user;
		public final String pass;

		Entry(String host, int port, String user, String pass) {
			this.host = host;
			this.port = port;
			this.user = user == null ? "" : user;
			this.pass = pass == null ? "" : pass;
			this.id = host + ":" + port + ":" + this.user;
		}
	}

	public static final class ImportResult {
		public final int added;
		public final String error;

		ImportResult(int added, String error) {
			this.added = added;
			this.error = error;
		}
	}

	public static final class TestResult {
		public final boolean alive;
		public final String verdict;

		TestResult(boolean alive, String verdict) {
			this.alive = alive;
			this.verdict = verdict;
		}
	}

	/** Storage seam so parsing and slot logic stay unit-testable without Android. */
	interface Storage {
		String get(String key);

		void put(String key, String value);
	}

	private final Storage storage;

	ProxyStore(Storage storage) {
		this.storage = storage;
	}

	public static ProxyStore forApp() {
		Context context = ContextHolder.getAppContext();
		SharedPreferences preferences =
				context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
		return new ProxyStore(new Storage() {
			@Override
			public String get(String key) {
				return preferences.getString(key, null);
			}

			@Override
			public void put(String key, String value) {
				SharedPreferences.Editor editor = preferences.edit();
				if (value == null) {
					editor.remove(key);
				} else {
					editor.putString(key, value);
				}
				editor.apply();
			}
		});
	}

	public List<Entry> list() {
		return Collections.unmodifiableList(loadEntries());
	}

	public Entry find(String id) {
		if (id == null) {
			return null;
		}
		for (Entry entry : loadEntries()) {
			if (entry.id.equals(id)) {
				return entry;
			}
		}
		return null;
	}

	/** Saves a proxy, returning a short validation error or null on success. */
	public String add(String host, int port, String user, String pass) {
		if (host == null || host.trim().isEmpty()) {
			return "Host is required";
		}
		if (port < 1 || port > 65535) {
			return "Port must be 1-65535";
		}
		Entry entry = new Entry(host.trim(), port, user, pass);
		List<Entry> entries = loadEntries();
		for (Entry existing : entries) {
			if (existing.id.equals(entry.id)) {
				return "Proxy already saved";
			}
		}
		entries.add(entry);
		saveEntries(entries);
		return null;
	}

	/** Parses {@code host:port[:user[:pass]]} lines; blank and # lines are skipped. */
	public ImportResult importText(String text) {
		if (text == null || text.trim().isEmpty()) {
			return new ImportResult(0, "No proxy text");
		}
		int added = 0;
		String error = null;
		String[] lines = text.split("\r?\n", -1);
		for (int i = 0; i < lines.length; i++) {
			String line = lines[i].trim();
			if (line.isEmpty() || line.startsWith("#")) {
				continue;
			}
			String[] parts = line.split(":", 4);
			if (parts.length < 2) {
				if (error == null) {
					error = lineError(i, "expected host:port");
				}
				continue;
			}
			int port;
			try {
				port = Integer.parseInt(parts[1].trim());
			} catch (NumberFormatException ex) {
				if (error == null) {
					error = lineError(i, "invalid port");
				}
				continue;
			}
			String user = parts.length > 2 ? parts[2] : "";
			String pass = parts.length > 3 ? parts[3] : "";
			String addError = add(parts[0], port, user, pass);
			if (addError == null) {
				added++;
			} else if (error == null) {
				error = lineError(i, addError);
			}
		}
		return new ImportResult(added, error);
	}

	public void remove(String id) {
		if (id == null) {
			return;
		}
		List<Entry> entries = loadEntries();
		if (entries.removeIf(entry -> entry.id.equals(id))) {
			saveEntries(entries);
		}
	}

	/** Verifies that the proxy accepts a CONNECT to a stable public endpoint. */
	public TestResult test(Entry entry) {
		if (entry == null) {
			return new TestResult(false, "No proxy");
		}
		// shortcut: a proxy that filters 1.1.1.1:80 reads as dead; add a
		// configurable probe target if users hit that.
		try (Socket socket = Socks5Tunnel.connect("1.1.1.1", 80,
				entry.host, entry.port, entry.user, entry.pass, 4000, 4000)) {
			return new TestResult(true, "Alive");
		} catch (IOException ex) {
			String message = ex.getMessage();
			return new TestResult(false,
					message == null || message.isEmpty() ? "Unreachable" : message);
		}
	}

	public String proxyIdForTab(Object storageKey, int slotIndex) {
		if (storageKey == null || slotIndex < 0) {
			return null;
		}
		List<String> slots = loadSlots(storageKey);
		return slotIndex < slots.size() ? slots.get(slotIndex) : null;
	}

	public void assignProxyToTab(Object storageKey, int slotIndex, String proxyId) {
		if (storageKey == null || slotIndex < 0) {
			return;
		}
		List<String> slots = loadSlots(storageKey);
		while (slots.size() <= slotIndex) {
			slots.add(null);
		}
		slots.set(slotIndex, proxyId);
		saveSlots(storageKey, slots);
	}

	public void clearProxyForTab(Object storageKey, int slotIndex) {
		if (storageKey == null || slotIndex < 0) {
			return;
		}
		List<String> slots = loadSlots(storageKey);
		if (slotIndex >= slots.size()) {
			return;
		}
		slots.set(slotIndex, null);
		while (!slots.isEmpty() && slots.get(slots.size() - 1) == null) {
			slots.remove(slots.size() - 1);
		}
		saveSlots(storageKey, slots);
	}

	private static String lineError(int zeroBasedLine, String message) {
		return "Line " + (zeroBasedLine + 1) + ": " + message;
	}

	private List<Entry> loadEntries() {
		List<Entry> entries = new ArrayList<>();
		String raw = storage.get(KEY_ENTRIES);
		if (raw == null || raw.isEmpty()) {
			return entries;
		}
		for (String line : raw.split("\n", -1)) {
			if (line.isEmpty()) {
				continue;
			}
			String[] fields = line.split("\t", -1);
			if (fields.length != 4) {
				continue;
			}
			try {
				entries.add(new Entry(decode(fields[0]), Integer.parseInt(fields[1]),
						decode(fields[2]), decode(fields[3])));
			} catch (RuntimeException ignored) {
				// Ignore a single unreadable row instead of dropping the whole store.
			}
		}
		return entries;
	}

	private void saveEntries(List<Entry> entries) {
		if (entries.isEmpty()) {
			storage.put(KEY_ENTRIES, null);
			return;
		}
		StringBuilder builder = new StringBuilder();
		for (Entry entry : entries) {
			if (builder.length() > 0) {
				builder.append('\n');
			}
			builder.append(encode(entry.host)).append('\t')
					.append(entry.port).append('\t')
					.append(encode(entry.user)).append('\t')
					.append(encode(entry.pass));
		}
		storage.put(KEY_ENTRIES, builder.toString());
	}

	private List<String> loadSlots(Object storageKey) {
		List<String> slots = new ArrayList<>();
		String raw = storage.get(SLOT_PREFIX + storageKey);
		if (raw == null || raw.isEmpty()) {
			return slots;
		}
		for (String token : raw.split("\n", -1)) {
			slots.add(token.isEmpty() ? null : decode(token));
		}
		return slots;
	}

	private void saveSlots(Object storageKey, List<String> slots) {
		if (slots.isEmpty()) {
			storage.put(SLOT_PREFIX + storageKey, null);
			return;
		}
		StringBuilder builder = new StringBuilder();
		for (int i = 0; i < slots.size(); i++) {
			if (i > 0) {
				builder.append('\n');
			}
			String id = slots.get(i);
			if (id != null) {
				builder.append(encode(id));
			}
		}
		storage.put(SLOT_PREFIX + storageKey, builder.toString());
	}

	private static String encode(String value) {
		try {
			return URLEncoder.encode(value, "UTF-8");
		} catch (UnsupportedEncodingException impossible) {
			throw new IllegalStateException(impossible);
		}
	}

	private static String decode(String value) {
		try {
			return URLDecoder.decode(value, "UTF-8");
		} catch (UnsupportedEncodingException impossible) {
			throw new IllegalStateException(impossible);
		}
	}
}
