/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

package io.github.h3nb.jlmodplus.net;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

public class ProxyStoreImportTest {
	private MapStorage storage;
	private ProxyStore store;

	@BeforeEach
	public void setUp() {
		storage = new MapStorage();
		store = new ProxyStore(storage);
	}

	@Test
	public void importsMixedLinesAndSkipsComments() {
		ProxyStore.ImportResult result = store.importText(
				"# saved proxies\n"
						+ "\n"
						+ "proxy.example:1080\n"
						+ "1.2.3.4:1081:alice:s3cr3t\n"
						+ "host.example:1082:bob\n"
						+ "colon.example:1083:carol:pa:ss\n");

		assertEquals(4, result.added);
		assertNull(result.error);
		assertEquals(4, store.list().size());
		assertEquals("alice", store.find("1.2.3.4:1081:alice").user);
		assertEquals("s3cr3t", store.find("1.2.3.4:1081:alice").pass);
		assertEquals("bob", store.find("host.example:1082:bob").user);
		assertEquals("", store.find("host.example:1082:bob").pass);
		assertEquals("pa:ss", store.find("colon.example:1083:carol").pass);
	}

	@Test
	public void reportsFirstInvalidLineAndKeepsValidOnes() {
		ProxyStore.ImportResult result = store.importText(
				"ok.example:1080\n"
						+ "bad.example:notaport\n"
						+ "also-bad\n"
						+ "good.example:1081\n");

		assertEquals(2, result.added);
		assertNotNull(result.error);
		assertTrue(result.error.contains("Line 2"));
	}

	@Test
	public void duplicateIdsAreRejected() {
		assertNull(store.add("proxy.example", 1080, "", ""));
		assertNotNull(store.add("proxy.example", 1080, "", ""));
		assertEquals(1, store.list().size());
	}

	@Test
	public void invalidPortsAreRejected() {
		assertNotNull(store.add("proxy.example", 0, "", ""));
		assertNotNull(store.add("proxy.example", 65536, "", ""));
		assertEquals(0, store.list().size());
	}

	@Test
	public void slotsAreIndependentAndPersist() {
		store.assignProxyToTab("app-key", 1, "proxy.example:1080:");

		ProxyStore reopened = new ProxyStore(storage);
		assertNull(reopened.proxyIdForTab("app-key", 0));
		assertEquals("proxy.example:1080:", reopened.proxyIdForTab("app-key", 1));
		assertNull(reopened.proxyIdForTab("other-key", 1));

		reopened.clearProxyForTab("app-key", 1);
		assertNull(reopened.proxyIdForTab("app-key", 1));
	}

	private static final class MapStorage implements ProxyStore.Storage {
		private final Map<String, String> values = new HashMap<>();

		@Override
		public String get(String key) {
			return values.get(key);
		}

		@Override
		public void put(String key, String value) {
			if (value == null) {
				values.remove(key);
			} else {
				values.put(key, value);
			}
		}
	}
}
