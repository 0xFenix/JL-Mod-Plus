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
 * Copyright 2017-2018 Nikita Shakarun
 * Licensed under the Apache License, Version 2.0
 * Ported for iOS/miniJVM — no changes needed (100% pure Java).
 */
package javax.microedition.lcdui.game;

import javax.microedition.lcdui.Graphics;

public abstract class Layer {
	int x;
	int y;
	int width;
	int height;
	boolean visible = true;

	Layer(int width, int height) {
		setWidthImpl(width);
		setHeightImpl(height);
	}

	public void setPosition(int x, int y) { this.x = x; this.y = y; }
	public void move(int dx, int dy) { x += dx; y += dy; }
	public final int getX() { return x; }
	public final int getY() { return y; }
	public final int getWidth() { return width; }
	public final int getHeight() { return height; }
	public void setVisible(boolean visible) { this.visible = visible; }
	public final boolean isVisible() { return visible; }
	public abstract void paint(Graphics g);

	void setWidthImpl(int width) {
		if (width < 0) throw new IllegalArgumentException();
		this.width = width;
	}

	void setHeightImpl(int height) {
		if (height < 0) throw new IllegalArgumentException();
		this.height = height;
	}
}
