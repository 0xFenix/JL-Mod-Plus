package javax.microedition.rms;

import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertSame;

import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicReference;

import javax.microedition.shell.MidletTabRouter;

import org.junit.After;
import org.junit.Test;

public class RecordStoreTabIsolationTest {
	private static Object managerForCurrentThread() throws Exception {
		Method method = RecordStore.class.getDeclaredMethod("managerForCurrentThread");
		method.setAccessible(true);
		return method.invoke(null);
	}

	private static Object resolveOnTab(int tabId) throws Exception {
		AtomicReference<Object> resolved = new AtomicReference<>();
		AtomicReference<RuntimeException> failure = new AtomicReference<>();
		Thread worker = new Thread(() -> {
			try {
				resolved.set(managerForCurrentThread());
			} catch (Exception e) {
				failure.set(new RuntimeException(e));
			}
		});
		MidletTabRouter.register(tabId, worker, thread -> thread == worker, new Object());
		try {
			worker.start();
			worker.join();
		} finally {
			MidletTabRouter.unregister(tabId);
		}
		if (failure.get() != null) {
			throw failure.get();
		}
		return resolved.get();
	}

	@After
	public void tearDown() {
		MidletTabRouter.unregister(1);
		MidletTabRouter.unregister(2);
		MidletTabRouter.unregister(5);
		RecordStore.removeManagerForTab(0);
		RecordStore.removeManagerForTab(1);
		RecordStore.removeManagerForTab(2);
		RecordStore.removeManagerForTab(5);
	}

	@Test
	public void differentTabsResolveToDifferentManagers() throws Exception {
		assertNotSame(resolveOnTab(1), resolveOnTab(2));
	}

	@Test
	public void sameTabReusesManagerUntilRemoved() throws Exception {
		Object first = resolveOnTab(5);
		Object second = resolveOnTab(5);
		assertSame(first, second);
		RecordStore.removeManagerForTab(5);
		assertNotSame(first, resolveOnTab(5));
	}
}
