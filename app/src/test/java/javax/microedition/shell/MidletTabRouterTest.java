/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
package javax.microedition.shell;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;

import org.junit.After;
import org.junit.Test;

public class MidletTabRouterTest {
	@After
	public void clearRouter() {
		MidletTabRouter.clear();
	}

	@Test
	public void exactThreadMatchWinsOverGuestPredicate() {
		Thread first = new Thread();
		Thread second = new Thread();
		Object firstRuntime = new Object();
		Object secondRuntime = new Object();
		MidletTabRouter.register(1, first, thread -> true, firstRuntime);
		MidletTabRouter.register(2, second, thread -> true, secondRuntime);

		assertEquals(2, MidletTabRouter.tabForThread(second));
		assertSame(secondRuntime, MidletTabRouter.runtimeForTab(2));
		assertSame(first, MidletTabRouter.mainThreadForTab(1));
	}

	@Test
	public void guestPredicateResolvesWorkerThreads() {
		Thread main = new Thread();
		Thread worker = new Thread();
		MidletTabRouter.register(1, main, thread -> thread == worker, new Object());

		assertEquals(1, MidletTabRouter.tabForThread(worker));
		assertEquals(MidletTabRouter.NO_TAB, MidletTabRouter.tabForThread(new Thread()));
	}

	@Test
	public void guestKeysBindByIdentity() {
		Object key = new Object();
		MidletTabRouter.register(1, new Thread(), null, new Object());
		MidletTabRouter.bindGuestKey(1, key);

		assertEquals(1, MidletTabRouter.tabForGuestKey(key));
		assertEquals(MidletTabRouter.NO_TAB, MidletTabRouter.tabForGuestKey(new Object()));
		MidletTabRouter.unregister(1);
		assertEquals(MidletTabRouter.NO_TAB, MidletTabRouter.tabForGuestKey(key));
		assertNull(MidletTabRouter.runtimeForTab(1));
		assertEquals(0, MidletTabRouter.tabCount());
	}

	@Test
	public void selectionIsIndependentFromRecords() {
		MidletTabRouter.setSelectedTab(3);
		assertEquals(3, MidletTabRouter.selectedTabId());
		MidletTabRouter.clear();
		assertEquals(MidletTabRouter.NO_TAB, MidletTabRouter.selectedTabId());
	}
}
