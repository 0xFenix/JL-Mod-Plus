/*
 * Derived from J2ME-Decade (iOS Edition) <https://github.com/darkrose00x-ux/j2me-ios>,
 * licensed under the Apache License, Version 2.0. That project states its J2ME API
 * layer is ported from J2ME-Loader <https://github.com/nikita36078/J2ME-Loader>,
 * whose javax.microedition sources are Copyright 2012 Kulikov Dmitriy,
 * 2017-2020 Nikita Shakarun, 2019-2023 Yury Kharchenko, Apache License 2.0.
 *
 * JL-Mod Plus modifications: removed the M3G (javax.microedition.m3g), MascotCapsule
 * micro3D, JBlend/Vodafone J3D, Bluetooth, Location and AMMS packages, which are
 * outside the iOS runtime scope.
 */
/*
 * Copyright 2012 Kulikov Dmitriy
 * Copyright 2017 Nikita Shakarun
 * Ported for iOS/miniJVM — removed Android Toast/ContextHolder/ViewHandler.
 */
package javax.microedition.lcdui.event;

import javax.microedition.util.ArrayStack;

public class RunnableEvent extends Event {
	private static final ArrayStack<RunnableEvent> recycled = new ArrayStack<>();
	private static int queued;

	private Runnable runnable;

	public static Event getInstance(Runnable runnable) {
		RunnableEvent instance = recycled.pop();
		if (instance == null) {
			instance = new RunnableEvent();
		}
		instance.runnable = runnable;
		return instance;
	}

	@Override
	public void process() {
		runnable.run();
	}

	@Override
	public void recycle() {
		runnable = null;
		recycled.push(this);
	}

	@Override
	public void enterQueue() {
		if (++queued > 50 && EventQueue.isImmediate()) {
			EventQueue.setImmediate(false);
			System.out.println("[RunnableEvent] Immediate mode disabled due to stack overflow");
		}
	}

	@Override
	public void leaveQueue() {
		queued--;
	}

	@Override
	public boolean placeableAfter(Event event) {
		return true;
	}
}
