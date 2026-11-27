/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */
package javax.microedition.lcdui.keyboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import org.junit.jupiter.api.Test;

public class VirtualKeyboardLayoutSnapshotTest {
	private static VirtualKeyboardLayoutSnapshot legacy(float offset) {
		return legacy(3, offset);
	}

	private static VirtualKeyboardLayoutSnapshot legacy(int variant, float offset) {
		return VirtualKeyboardLayoutSnapshot.legacy(
				variant,
				new boolean[] { true, false },
				new int[] { -1, 0 },
				new int[] { 2, 4 },
				new float[] { offset, 0.0f },
				new float[] { 0.0f, 1.0f },
				new float[] { 1.0f, 1.0f });
	}

	@Test
	public void snapshotOwnsImmutableCopies() {
		boolean[] visible = { true, false };
		int[] origins = { -1, 0 };
		int[] modes = { 2, 4 };
		float[] x = { 3.0f, 0.0f };
		float[] y = { 0.0f, 1.0f };
		float[] scales = { 1.0f, 1.0f };
		VirtualKeyboardLayoutSnapshot snapshot = VirtualKeyboardLayoutSnapshot.legacy(
				3, visible, origins, modes, x, y, scales);

		visible[0] = false;
		origins[0] = 99;
		x[0] = 50.0f;
		scales[0] = 4.0f;

		assertEquals(legacy(3.0f), snapshot);
	}

	@Test
	public void semanticGeometryChangeIsDirty() {
		assertNotEquals(legacy(3.0f), legacy(5.0f));
	}

	@Test
	public void groupedControlGeometryChangeIsDirty() {
		VirtualKeyboardLayoutSnapshot baseline = legacy(3.0f).withGroupedControls(
				true, false,
				0.20f, 0.82f, 0.16f,
				0.20f, 0.82f, 0.16f);
		VirtualKeyboardLayoutSnapshot changed = legacy(3.0f).withGroupedControls(
				true, false,
				0.25f, 0.82f, 0.16f,
				0.20f, 0.82f, 0.16f);

		assertNotEquals(baseline, changed);
	}
}
