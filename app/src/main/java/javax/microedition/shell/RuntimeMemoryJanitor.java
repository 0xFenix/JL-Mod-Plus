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

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Trims runtime caches while a game runs, so a session left open for days does not keep
 * growing. One daemon thread wakes once a minute and compares the elapsed time against the
 * two configured intervals.
 *
 * <p>Both tasks are best effort. Clearing caches only frees bitmaps the runtime can rebuild,
 * and {@link System#gc()} cannot release anything the runtime still references, so this
 * cannot rescue a session that is genuinely out of memory.</p>
 */
final class RuntimeMemoryJanitor {

	interface Tasks {
		/** Drops cached bitmaps; the runtime recaptures them when they are next needed. */
		void clearCaches();
	}

	private static final long TICK_SECONDS = 60L;

	private final Tasks tasks;
	private ScheduledExecutorService executor;
	private volatile int trimMinutes;
	private volatile int gcMinutes;
	private volatile long lastTrimNanos;
	private volatile long lastGcNanos;

	RuntimeMemoryJanitor(Tasks tasks) {
		this.tasks = tasks;
	}

	/** Minutes between cache trims and between collections; 0 disables that timer. */
	void setIntervals(int trimMinutes, int gcMinutes) {
		this.trimMinutes = Math.max(trimMinutes, 0);
		this.gcMinutes = Math.max(gcMinutes, 0);
		start();
	}

	void start() {
		synchronized (this) {
			if (executor != null) return;
			long now = System.nanoTime();
			lastTrimNanos = now;
			lastGcNanos = now;
			executor = Executors.newSingleThreadScheduledExecutor(runnable -> {
				Thread thread = new Thread(runnable, "runtime-memory-janitor");
				thread.setDaemon(true);
				return thread;
			});
			executor.scheduleWithFixedDelay(this::tick, TICK_SECONDS, TICK_SECONDS, TimeUnit.SECONDS);
		}
	}

	void stop() {
		ScheduledExecutorService current;
		synchronized (this) {
			current = executor;
			executor = null;
		}
		if (current != null) current.shutdownNow();
	}

	/** Runs the cache trim now; also used when Android reports memory pressure. */
	void trimNow() {
		lastTrimNanos = System.nanoTime();
		tasks.clearCaches();
	}

	private void tick() {
		try {
			long now = System.nanoTime();
			int trim = trimMinutes;
			if (trim > 0 && now - lastTrimNanos >= TimeUnit.MINUTES.toNanos(trim)) {
				trimNow();
			}
			int gc = gcMinutes;
			if (gc > 0 && now - lastGcNanos >= TimeUnit.MINUTES.toNanos(gc)) {
				lastGcNanos = now;
				System.gc();
			}
		} catch (RuntimeException ignored) {
			// A janitor must never take the runtime down.
		}
	}
}
