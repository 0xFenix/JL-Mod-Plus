/*
 * Modified for JL-Mod Plus.
 * Copyright 2012 Kulikov Dmitriy
 * Copyright 2017-2018 Nikita Shakarun
 * Copyright 2020-2026 Yury Kharchenko
 *
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

package javax.microedition.lcdui;

import android.util.Log;

import androidx.appcompat.app.AlertDialog;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

import javax.microedition.lcdui.event.Event;
import javax.microedition.lcdui.event.EventQueue;
import javax.microedition.lcdui.event.RunnableEvent;
import javax.microedition.lcdui.event.SimpleEvent;
import javax.microedition.midlet.MIDlet;
import javax.microedition.shell.MemoryDiscoveryBridge;
import javax.microedition.shell.MicroActivity;
import javax.microedition.shell.MidletTabRouter;
import javax.microedition.shell.MidletThread;
import javax.microedition.util.ContextHolder;
import io.github.h3nb.jlmodplus.ui.LegacyThemeColors;

@SuppressWarnings("unused")
public class Display {
	public static final int LIST_ELEMENT = 1;
	public static final int CHOICE_GROUP_ELEMENT = 2;
	public static final int ALERT = 3;

	public static final int COLOR_BACKGROUND = 0;
	public static final int COLOR_FOREGROUND = 1;
	public static final int COLOR_HIGHLIGHTED_BACKGROUND = 2;
	public static final int COLOR_HIGHLIGHTED_FOREGROUND = 3;
	public static final int COLOR_BORDER = 4;
	public static final int COLOR_HIGHLIGHTED_BORDER = 5;

	private static final int[] COLORS =
			{
					0xFFD0D0D0,
					0xFF000080,
					0xFF000080,
					0xFFFFFFFF,
					0xFFFFFFFF,
					0xFF000080
			};

	/** Per-tab Display hosts. Tab ids come from the AMS registry; id 0 is the
	 * implicit single-tab fallback used when no tab is registered (unit tests). */
	private static final Map<Integer, Display> INSTANCES = new HashMap<>();
	/** Per-tab MIDP foreground request/grant state. */
	private static final Map<Integer, Foreground> FOREGROUNDS = new HashMap<>();
	/** Per-tab LCDUI event queues with their worker threads. */
	private static final Map<Integer, EventQueue> QUEUES = new HashMap<>();
	private static final Map<Thread, Integer> QUEUE_WORKERS = new HashMap<>();

	private static final class Foreground {
		boolean requested;
		boolean granted;
		long generation;
	}

	private final int tabId;

	private volatile Displayable current;
	/** UI-confirmed presentation for non-Canvas Displayables. */
	private Displayable presented;
	/** Invalidates queued show requests when the displayable changes, including reusing an Alert. */
	private final AtomicLong currentRequestGeneration = new AtomicLong();
	/** Serializes current-screen and host-presentation facts. */
	private final Object stateLock = new Object();
	private boolean hostVisible;
	private boolean displayForeground;
	/** Rejects presentation updates from superseded Android foreground edges. */
	private long appliedForegroundGeneration;
	private ScreenChange screenChange;
	/**
	 * A missing Android surface must not indefinitely block all subsequent LCDUI callbacks.
	 * Normal screen changes complete on the host's readiness signal, not on this deadline.
	 */
	private static final long SCREEN_CHANGE_MAX_WAIT_MS = 3000L;

	/** A queue position that becomes runnable only after this Canvas is mount/surface-ready. */
	final class ScreenChange extends SimpleEvent {
		private final Canvas canvas;
		private final long requestGeneration;
		private final MicroActivity host;
		private volatile boolean ready;
		private boolean cancelled;
		private boolean mounted;
		private long showGeneration;
		private final Runnable readinessDeadline = this::onReadinessDeadline;

		private void onReadinessDeadline() {
			synchronized (stateLock) {
				if (screenChange != this) return;
				if (isReady()) {
					// An earlier guest callback can still occupy the event queue. Keep watching
					// until this ready transaction is consumed or its surface becomes unavailable.
					ViewHandler.postDelayed(readinessDeadline, SCREEN_CHANGE_MAX_WAIT_MS);
					return;
				}
				Log.w("Display", "Canvas presentation did not become ready; releasing LCDUI queue");
				cancelScreenChangeLocked();
			}
		}

		ScreenChange(Canvas canvas, long requestGeneration, MicroActivity host) {
			this.canvas = canvas;
			this.requestGeneration = requestGeneration;
			this.host = host;
			asGuestCallback();
		}

		@Override
		public boolean isReady() {
			return ready;
		}

		private void updateReady() {
			ready = cancelled || (mounted && showGeneration != 0L);
			if (ready) queueFor(tabId).signalEventReady();
		}

		synchronized void mounted() {
			if (cancelled) return;
			mounted = true;
			updateReady();
		}

		synchronized void surfaceReady(long generation) {
			if (cancelled) return;
			showGeneration = generation;
			updateReady();
		}

		synchronized void surfaceUnavailable() {
			if (cancelled) return;
			showGeneration = 0L;
			updateReady();
		}

		synchronized void cancel() {
			cancelled = true;
			updateReady();
		}

		@Override
		public void process() {
			long generation;
			synchronized (stateLock) {
				if (screenChange != this) return;
				screenChange = null;
				ViewHandler.removeCallbacks(readinessDeadline);
				canvas.clearScreenChange(this);
				synchronized (this) {
					if (cancelled || current != canvas
							|| currentRequestGeneration.get() != requestGeneration
							|| ContextHolder.getActivity() != host) return;
					generation = showGeneration;
				}
			}
			canvas.finishScreenChange(generation);
		}
	}

	private void cancelScreenChangeLocked() {
		if (screenChange == null) return;
		ScreenChange old = screenChange;
		screenChange = null;
		ViewHandler.removeCallbacks(old.readinessDeadline);
		old.cancel();
		old.canvas.clearScreenChange(old);
	}

	private void beginScreenChangeLocked(Displayable target, long generation) {
		if (!(target instanceof Canvas canvas) || !hostVisible || !displayForeground) return;
		MicroActivity host = ContextHolder.getActivity();
		if (host == null) return;
		ScreenChange change = new ScreenChange(canvas, generation, host);
		screenChange = change;
		canvas.beginScreenChange(change);
		queueFor(tabId).postQueuedEvent(change);
		// A mounted SurfaceView is not guaranteed to produce a surfaceCreated callback.
		// Preserve normal startup ordering but bound the queue's head-of-line wait.
		ViewHandler.postDelayed(change.readinessDeadline, SCREEN_CHANGE_MAX_WAIT_MS);
	}

	/** Accept only a mount result from the host which owns the pending request. */
	public void onHostMounted(Displayable target, long generation, MicroActivity host) {
		synchronized (stateLock) {
			ScreenChange change = screenChange;
			if (change != null && change.canvas == target
					&& change.requestGeneration == generation && change.host == host) {
				change.mounted();
			}
		}
	}

	public void onHostMountFailed(Displayable target, long generation, MicroActivity host) {
		synchronized (stateLock) {
			ScreenChange change = screenChange;
			if (change != null && change.canvas == target
					&& change.requestGeneration == generation && change.host == host) {
				cancelScreenChangeLocked();
			}
		}
	}


	/**
	 * Applies the Display-owned presentation facts while their transaction lock is still held.
	 * This prevents a guest-thread setCurrent() snapshot from arriving after a newer host/UI edge.
	 */
	private void reconcileCanvasLocked(Displayable displayable, boolean isCurrent) {
		if (displayable instanceof Canvas canvas) {
			canvas.updatePresentationState(isCurrent, hostVisible, displayForeground);
		}
	}

	public static synchronized Display getDisplay(MIDlet midlet) {
		int tabId = selectedTabOrDefault();
		if (midlet != null) {
			int owned = MidletTabRouter.tabForGuestKey(midlet);
			if (owned != MidletTabRouter.NO_TAB) {
				tabId = owned;
			} else {
				int threadTab = MidletTabRouter.tabForThread(Thread.currentThread());
				if (threadTab != MidletTabRouter.NO_TAB) {
					tabId = threadTab;
				}
			}
		}
		Display display = INSTANCES.get(tabId);
		if (display == null && midlet != null) {
			Foreground foreground = foregroundFor(tabId);
			display = new Display(tabId, foreground.granted, foreground.generation);
			INSTANCES.put(tabId, display);
		}
		return display;
	}

	private Display(int tabId, boolean foregroundGranted, long generation) {
		this.tabId = tabId;
		displayForeground = foregroundGranted;
		appliedForegroundGeneration = generation;
		MicroActivity activity = ContextHolder.getActivity();
		hostVisible = activity != null && activity.isVisible();
	}

	/** Returns the live Display of a tab without creating one, or null. */
	public static synchronized Display forTab(int tabId) {
		return INSTANCES.get(tabId);
	}

	/** Resolves the selected tab, defaulting to the implicit single-tab id. */
	private static int selectedTabOrDefault() {
		int tabId = MidletTabRouter.selectedTabId();
		return tabId == MidletTabRouter.NO_TAB ? 0 : tabId;
	}

	/** Resolves the calling thread's tab: owner, queue worker, then selected. */
	private static int tabForCurrentThreadOrSelected() {
		int tabId = MidletTabRouter.tabForThread(Thread.currentThread());
		if (tabId != MidletTabRouter.NO_TAB) {
			return tabId;
		}
		synchronized (Display.class) {
			Integer queued = QUEUE_WORKERS.get(Thread.currentThread());
			if (queued != null) {
				return queued;
			}
		}
		return selectedTabOrDefault();
	}

	private static Foreground foregroundFor(int tabId) {
		Foreground foreground = FOREGROUNDS.get(tabId);
		if (foreground == null) {
			foreground = new Foreground();
			FOREGROUNDS.put(tabId, foreground);
		}
		return foreground;
	}

	private static synchronized EventQueue queueFor(int tabId) {
		EventQueue queue = QUEUES.get(tabId);
		if (queue == null) {
			queue = new EventQueue();
			queue.startProcessing();
			QUEUES.put(tabId, queue);
			Thread worker = queue.getWorkerThread();
			if (worker != null) {
				QUEUE_WORKERS.put(worker, tabId);
			}
		}
		return queue;
	}

	public static synchronized void initDisplay() {
		initDisplay(selectedTabOrDefault());
	}

	public static synchronized void initDisplay(int tabId) {
		INSTANCES.remove(tabId);
		FOREGROUNDS.remove(tabId);
		EventQueue queue = QUEUES.remove(tabId);
		if (queue != null) {
			Thread worker = queue.getWorkerThread();
			if (worker != null) {
				QUEUE_WORKERS.remove(worker);
			}
			queue.stopProcessing();
		}
	}

	/**
	 * Starts a new host foreground edge. It remains pending until the LCDUI barrier
	 * grants this exact generation, independently of guest startApp() completion.
	 */
	public static long requestForeground() {
		return requestForeground(selectedTabOrDefault());
	}

	public static long requestForeground(int tabId) {
		Display current;
		long generation;
		synchronized (Display.class) {
			Foreground foreground = foregroundFor(tabId);
			foreground.requested = true;
			foreground.granted = false;
			generation = ++foreground.generation;
			current = INSTANCES.get(tabId);
		}
		if (current != null) {
			current.updateForegroundGranted(false, generation);
		}
		return generation;
	}

	/**
	 * Revokes display ownership synchronously at the Android visibility edge and invalidates every
	 * older foreground grant attempt.
	 */
	public static void revokeForeground() {
		revokeForeground(selectedTabOrDefault());
	}

	public static void revokeForeground(int tabId) {
		Display current;
		long generation;
		synchronized (Display.class) {
			Foreground foreground = foregroundFor(tabId);
			foreground.requested = false;
			foreground.granted = false;
			generation = ++foreground.generation;
			current = INSTANCES.get(tabId);
		}
		if (current != null) {
			current.updateForegroundGranted(false, generation);
		}
	}

	/** Returns only foreground ownership committed by the LCDUI barrier, not a pending request. */
	public static synchronized long currentGrantedForegroundGeneration() {
		return currentGrantedForegroundGeneration(selectedTabOrDefault());
	}

	public static synchronized long currentGrantedForegroundGeneration(int tabId) {
		Foreground foreground = foregroundFor(tabId);
		return foreground.requested && foreground.granted
				? foreground.generation : 0L;
	}

	/**
	 * Grants display ownership only if the activation still belongs to the latest foreground edge.
	 * This fences rapid Home/return even when startApp() has not returned.
	 */
	public static synchronized long currentForegroundRequestGeneration() {
		return currentForegroundRequestGeneration(selectedTabOrDefault());
	}

	public static synchronized long currentForegroundRequestGeneration(int tabId) {
		Foreground foreground = foregroundFor(tabId);
		return foreground.requested ? foreground.generation : 0L;
	}

	public static synchronized boolean isForegroundRequestCurrent(long generation) {
		return isForegroundRequestCurrent(generation, selectedTabOrDefault());
	}

	public static synchronized boolean isForegroundRequestCurrent(long generation, int tabId) {
		Foreground foreground = foregroundFor(tabId);
		return generation != 0L
				&& foreground.requested
				&& generation == foreground.generation;
	}

	public static boolean grantForeground(long generation) {
		return grantForeground(generation, selectedTabOrDefault());
	}

	public static boolean grantForeground(long generation, int tabId) {
		Display current;
		synchronized (Display.class) {
			Foreground foreground = foregroundFor(tabId);
			if (!foreground.requested || generation != foreground.generation) {
				return false;
			}
			foreground.granted = true;
			current = INSTANCES.get(tabId);
		}
		if (current != null) {
			current.updateForegroundGranted(true, generation);
		}
		return true;
	}

	private void updateForegroundGranted(boolean granted, long generation) {
		synchronized (stateLock) {
			if (generation < appliedForegroundGeneration) {
				return;
			}
			appliedForegroundGeneration = generation;
			if (displayForeground == granted) {
				return;
			}
			displayForeground = granted;
			if (!granted) cancelScreenChangeLocked();
			reconcileCanvasLocked(current, true);
		}
	}

	/**
	 * Attaches the persisted guest Display state to a replacement Android host. The new Activity is
	 * still in onCreate, so presentation remains hidden until its onStart edge arrives.
	 */
	public void attachHost(MicroActivity activity) {
		Displayable target;
		long requestGeneration;
		synchronized (stateLock) {
			presented = null;
			hostVisible = false;
			cancelScreenChangeLocked();
			target = current;
			requestGeneration = currentRequestGeneration.incrementAndGet();
			reconcileCanvasLocked(target, true);
		}
		if (target instanceof Alert alert) {
			alert.detachHost();
			final long generation = requestGeneration;
			ViewHandler.postEvent(() -> showAlert(alert, generation));
		} else if (target != null) {
			target.clearDisplayableView();
			activity.setCurrent(target, requestGeneration, tabId);
		}
	}

	public void detachHost() {
		Displayable target;
		synchronized (stateLock) {
			presented = null;
			hostVisible = false;
			cancelScreenChangeLocked();
			target = current;
			currentRequestGeneration.incrementAndGet();
			reconcileCanvasLocked(target, true);
		}
		if (target instanceof Alert alert) {
			alert.detachHost();
		} else if (target != null) {
			target.clearDisplayableView();
		}
	}

	/** Updates host foreground access without changing the guest's current Displayable. */
	public void setHostVisible(boolean visible) {
		Canvas hiddenCanvas = null;
		synchronized (stateLock) {
			if (hostVisible == visible) {
				return;
			}
			hostVisible = visible;
			if (!visible) {
				cancelScreenChangeLocked();
				if (current instanceof Canvas canvas) hiddenCanvas = canvas;
			}
			reconcileCanvasLocked(current, true);
		}
		// MicroActivity calls this on Android main. Finish UI-owned cancellation now,
		// rather than allowing a rapid Home/return to bypass its queued cleanup.
		if (hiddenCanvas != null) hiddenCanvas.endHostPresentation();
	}

	public static void postEvent(Event event) {
		queueFor(tabForCurrentThreadOrSelected()).postEvent(event);
	}

	/** Enqueues a presentation callback without executing it under host ownership locks. */
	public static void postSerializedEvent(Event event) {
		queueFor(tabForCurrentThreadOrSelected()).postQueuedEvent(event);
	}

	/**
	 * Posts a non-blocking barrier after already queued LCDUI callbacks. Its continuation may
	 * commit host presentation ownership or signal AMS, but never executes guest lifecycle code.
	 */
	public static void postAfterPendingCallbacks(Runnable runnable) {
		queueFor(tabForCurrentThreadOrSelected()).postBarrier(runnable);
	}

	static EventQueue getEventQueue() {
		return queueFor(tabForCurrentThreadOrSelected());
	}

	public void setCurrent(Displayable displayable) {
		if (displayable == null) {
			// MIDP defines null as an AMS background request; guest current state is retained.
			MidletThread.requestBackground();
			return;
		}
		Displayable previous;
		long requestGeneration = 0L;
		Alert alert = null;
		boolean showCanvasAfterClosingAlert;
		synchronized (stateLock) {
			previous = this.current;
			if (previous instanceof Alert && displayable instanceof Alert) {
				throw new IllegalArgumentException();
			}
			if (displayable == previous) {
				// MIDP treats this as a foreground request. JL-Mod deliberately leaves that request
				// to AMS policy; guest code must never foreground the Android task directly.
				return;
			}
			requestGeneration = currentRequestGeneration.incrementAndGet();
			// The former host mount no longer certifies presentation for a new request.
			presented = null;
			cancelScreenChangeLocked();
			this.current = displayable;
			MemoryDiscoveryBridge.setCurrentDisplayable(displayable);
			if (displayable instanceof Alert nextAlert) {
				alert = nextAlert;
				alert.setNextDisplayable(previous);
			}
			showCanvasAfterClosingAlert =
					previous instanceof Alert && displayable instanceof Canvas;
			reconcileCanvasLocked(previous, false);
			beginScreenChangeLocked(displayable, requestGeneration);
			if (!showCanvasAfterClosingAlert) {
				reconcileCanvasLocked(displayable, true);
			}
		}
		if (previous instanceof Alert previousAlert) {
			previousAlert.close();
		}
		if (showCanvasAfterClosingAlert) {
			synchronized (stateLock) {
				if (current == displayable
						&& currentRequestGeneration.get() == requestGeneration) {
					reconcileCanvasLocked(displayable, true);
				}
			}
		}
		MicroActivity activity = ContextHolder.getActivity();
		// Only the selected tab mounts screens on the shared host. A background tab keeps
		// its guest current state; it is presented when the user switches to it.
		if (activity == null || tabId != MidletTabRouter.selectedTabId()) {
			return;
		}
		if (alert != null) {
			Alert requestedAlert = alert;
			final long generation = requestGeneration;
			ViewHandler.postEvent(() -> showAlert(requestedAlert, generation));
		} else {
			activity.setCurrent(displayable, requestGeneration, tabId);
		}
	}

	public void setCurrent(Alert alert, Displayable displayable) {
		if (alert == null || displayable == null) {
			throw new NullPointerException();
		} else if (displayable instanceof Alert) {
			throw new IllegalArgumentException();
		}
		Displayable previous;
		long requestGeneration;
		synchronized (stateLock) {
			if (current instanceof Alert && current != alert) {
				// Display.setCurrent(Alert, ...) has the same restriction as the single-argument
				// overload: an Alert cannot replace another currently displayed Alert directly.
				throw new IllegalArgumentException();
			}
			if (current == alert) {
				alert.setNextDisplayable(displayable);
				MemoryDiscoveryBridge.setCurrentDisplayable(displayable);
				return;
			}
			previous = current;
			alert.setNextDisplayable(displayable);
			requestGeneration = currentRequestGeneration.incrementAndGet();
			// The former host mount no longer certifies presentation for a new request.
			presented = null;
			cancelScreenChangeLocked();
			current = alert;
			MemoryDiscoveryBridge.setCurrentDisplayable(displayable);
			reconcileCanvasLocked(previous, false);
		}
		if (previous instanceof Alert previousAlert) {
			previousAlert.close();
		}
		if (ContextHolder.getActivity() != null
				&& tabId == MidletTabRouter.selectedTabId()) {
			ViewHandler.postEvent(() -> showAlert(alert, requestGeneration));
		}
	}

	private void showAlert(Alert expectedAlert, long requestGeneration) {
		if (tabId != MidletTabRouter.selectedTabId()) {
			return;
		}
		synchronized (stateLock) {
			if (current != expectedAlert || currentRequestGeneration.get() != requestGeneration) {
				return;
			}
			AlertDialog alertDialog = expectedAlert.prepareDialog();
			if (current != expectedAlert || currentRequestGeneration.get() != requestGeneration) {
				expectedAlert.close();
				return;
			}
			alertDialog.show();
			presented = expectedAlert;
			styleAlertDialog(alertDialog);
			expectedAlert.onDialogShown(alertDialog);
			if (current != expectedAlert || currentRequestGeneration.get() != requestGeneration) {
				alertDialog.dismiss();
			}
		}
	}

	/** Reconciles a visible Alert while sharing the same transaction lock as setCurrent(). */
	void refreshAlert(Alert expectedAlert, AlertDialog expectedDialog) {
		synchronized (stateLock) {
			if (current != expectedAlert) {
				return;
			}
			expectedAlert.rebuildDialog(expectedDialog);
		}
	}

	/** Re-presents the guest current screen on the shared host (used on tab switch). */
	public void refreshHostPresentation() {
		Displayable target;
		long generation;
		synchronized (stateLock) {
			// Invalidate the last certified presentation so the host remounts below.
			presented = null;
			cancelScreenChangeLocked();
			generation = currentRequestGeneration.incrementAndGet();
			target = current;
		}
		MicroActivity activity = ContextHolder.getActivity();
		if (activity == null || tabId != MidletTabRouter.selectedTabId()) {
			return;
		}
		if (target instanceof Alert requestedAlert) {
			final long pending = generation;
			ViewHandler.postEvent(() -> showAlert(requestedAlert, pending));
		} else {
			activity.setCurrent(target, generation, tabId);
		}
	}

	/**
	 * Restores the pre-Alert startup state. This is intentionally separate from setCurrent(null):
	 * MIDP defines the latter as a background request and it must not clear the guest current
	 * Displayable.
	 */
	void restoreAfterAlert(Alert expectedAlert) {
		MicroActivity activity;
		long requestGeneration;
		synchronized (stateLock) {
			if (current != expectedAlert) {
				return;
			}
			requestGeneration = currentRequestGeneration.incrementAndGet();
			current = null;
			presented = null;
			activity = ContextHolder.getActivity();
		}
		if (activity != null && tabId == MidletTabRouter.selectedTabId()) {
			activity.setCurrent(null, requestGeneration, tabId);
		}
	}

	static void styleAlertDialog(AlertDialog alertDialog) {
		int accent = LegacyThemeColors.accent(alertDialog.getContext());
		if (alertDialog.getButton(AlertDialog.BUTTON_POSITIVE) != null) {
			alertDialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(accent);
		}
		if (alertDialog.getButton(AlertDialog.BUTTON_NEGATIVE) != null) {
			alertDialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(accent);
		}
		if (alertDialog.getButton(AlertDialog.BUTTON_NEUTRAL) != null) {
			alertDialog.getButton(AlertDialog.BUTTON_NEUTRAL).setTextColor(accent);
		}
	}

	/** Reports the mounted Displayable; a stale host completion cannot publish an old screen. */
	public void onHostPresented(Displayable displayable, long requestGeneration) {
		synchronized (stateLock) {
			if (current == displayable && currentRequestGeneration.get() == requestGeneration) {
				presented = displayable;
			}
		}
	}

	/** Clears a dismissed Alert which may remain current while command handling proceeds. */
	void onHostPresentationEnded(Displayable displayable) {
		synchronized (stateLock) {
			if (presented == displayable) presented = null;
		}
	}

	boolean isDisplayableShown(Displayable displayable) {
		synchronized (stateLock) {
			return current == displayable && presented == displayable
					&& hostVisible && displayForeground;
		}
	}

	public Displayable getCurrent() {
		return current;
	}

	public void callSerially(Runnable r) {
		queueFor(tabId).postEvent(RunnableEvent.getInstance(r).asGuestCallback());
	}

	public boolean flashBacklight(int duration) {
		return false;
	}

	/** @since MIDP 2.0 */
	public boolean vibrate(int duration) {
		return ContextHolder.vibrate(duration);
	}

	public void setCurrentItem(Item item) {
		Screen owner = item.getOwner();
		if (owner instanceof Form) {
			setCurrent(owner);
		} else {
			throw new IllegalStateException("Item is not owned by a Form");
		}
	}

	public int numAlphaLevels() {
		return 256;
	}

	public int numColors() {
		return Integer.MAX_VALUE;
	}

	public int getBestImageHeight(int imageType) {
		return 0;
	}

	public int getBestImageWidth(int imageType) {
		return 0;
	}

	public int getBorderStyle(boolean highlighted) {
		return highlighted ? Graphics.SOLID : Graphics.DOTTED;
	}

	public int getColor(int colorSpecifier) {
		return COLORS[colorSpecifier];
	}

	public boolean isColor() {
		return true;
	}
}
