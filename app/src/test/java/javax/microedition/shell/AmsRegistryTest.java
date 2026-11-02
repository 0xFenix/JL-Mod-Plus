/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
package javax.microedition.shell;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.List;

import org.junit.Test;

public class AmsRegistryTest {
	@Test
	public void addTabSelectsNewTabAndAssignsStableIds() {
		AmsRegistry registry = new AmsRegistry();
		AmsRegistry.Tab first = registry.addTab("1");
		AmsRegistry.Tab second = registry.addTab("2");

		assertNotNull(first);
		assertNotNull(second);
		assertEquals(1, first.id);
		assertEquals(2, second.id);
		assertEquals(2, registry.selectedId());
		assertEquals(2, registry.size());
	}

	@Test
	public void addTabRespectsMaxTabs() {
		AmsRegistry registry = new AmsRegistry(2);
		assertNotNull(registry.addTab("1"));
		assertNotNull(registry.addTab("2"));
		assertNull(registry.addTab("3"));
		assertTrue(registry.isFull());
		assertEquals(2, registry.size());
	}

	@Test
	public void defaultMaxTabsIsSix() {
		AmsRegistry registry = new AmsRegistry();
		for (int i = 0; i < AmsRegistry.MAX_TABS; i++) {
			assertNotNull(registry.addTab(String.valueOf(i + 1)));
		}
		assertNull(registry.addTab("overflow"));
		assertEquals(6, AmsRegistry.MAX_TABS);
	}

	@Test
	public void selectTabRejectsUnknownIds() {
		AmsRegistry registry = new AmsRegistry();
		AmsRegistry.Tab tab = registry.addTab("1");
		assertTrue(registry.selectTab(tab.id));
		assertFalse(registry.selectTab(999));
		assertEquals(tab.id, registry.selectedId());
	}

	@Test
	public void closeSelectedTabSelectsNeighbour() {
		AmsRegistry registry = new AmsRegistry();
		AmsRegistry.Tab first = registry.addTab("1");
		AmsRegistry.Tab second = registry.addTab("2");
		AmsRegistry.Tab third = registry.addTab("3");
		assertEquals(third.id, registry.selectedId());

		assertTrue(registry.closeTab(third.id));
		assertEquals(second.id, registry.selectedId());

		assertTrue(registry.closeTab(first.id));
		assertEquals(second.id, registry.selectedId());
		assertEquals(1, registry.size());
	}

	@Test
	public void closeLastTabIsRefused() {
		AmsRegistry registry = new AmsRegistry();
		AmsRegistry.Tab only = registry.addTab("1");
		assertFalse(registry.closeTab(only.id));
		assertFalse(registry.closeTab(999));
		assertEquals(1, registry.size());
	}

	@Test
	public void snapshotIsImmutableCopy() {		AmsRegistry registry = new AmsRegistry();
		registry.addTab("1");
		List<AmsRegistry.Tab> snapshot = registry.snapshot();
		assertEquals(1, snapshot.size());
		registry.addTab("2");
		assertEquals(1, snapshot.size());
		assertEquals(2, registry.snapshot().size());
	}

	@Test
	public void tabCarriesSuiteIdentityAndSurvivesReselection() {
		AmsRegistry registry = new AmsRegistry();
		AmsRegistry.Tab tab = registry.addTab("1", "/data/app/suiteA", 42L, "com.a.Main");
		assertEquals("/data/app/suiteA", tab.appPath);
		assertEquals(42L, tab.expectedAppId);
		assertEquals("com.a.Main", tab.mainClass);

		assertTrue(registry.setTabSuite(tab.id, "/data/app/suiteB", 77L, "com.b.Main"));
		AmsRegistry.Tab updated = registry.snapshot().get(0);
		assertEquals("/data/app/suiteB", updated.appPath);
		assertEquals(77L, updated.expectedAppId);
		assertEquals("com.b.Main", updated.mainClass);
		assertEquals(tab.id, registry.selectedId());

		assertFalse(registry.setTabSuite(999, "/x", 1L, "C"));
	}
}
