package com.retro.nes;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import javax.microedition.lcdui.Canvas;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import javax.microedition.shell.AppClassLoader;

public class NesCanvas extends Canvas implements Runnable {
    private final NesCartridge cart;
    private final NesPpu ppu;
    private final NesCpu cpu;
    private Thread emuThread;
    private volatile boolean running = false;

    // Joypad bitmask: 0: A, 1: B, 2: Select, 3: Start, 4: Up, 5: Down, 6: Left, 7: Right
    private static final int MASK_A = 1;
    private static final int MASK_B = 2;
    private static final int MASK_SELECT = 4;
    private static final int MASK_START = 8;
    private static final int MASK_UP = 16;
    private static final int MASK_DOWN = 32;
    private static final int MASK_LEFT = 64;
    private static final int MASK_RIGHT = 128;

    private int joypad = 0;

    public NesCanvas(InputStream romStream) throws Exception {
        cart = NesCartridge.load(romStream);
        ppu = new NesPpu(cart);
        cpu = new NesCpu(ppu, cart);
    }

    public void start() {
        if (running) return;
        running = true;
        emuThread = new Thread(this, "NES-Emulator");
        emuThread.start();
    }

    public void stop() {
        running = false;
        if (emuThread != null) {
            try {
                emuThread.join(500);
            } catch (InterruptedException ignored) {}
        }
    }

    @Override
    public void run() {
        long frameTimeNanos = 1_000_000_000L / 60; // 60 FPS
        while (running) {
            long start = System.nanoTime();

            // Run 1 frame (262 scanlines)
            cpu.joy1State = joypad;
            for (int sl = 0; sl < 262; sl++) {
                ppu.stepScanline();
                // ~113.6 CPU cycles per scanline
                int cyclesTarget = 114;
                int cycDone = 0;
                while (cycDone < cyclesTarget) {
                    cycDone += cpu.step();
                }
            }

            repaint();

            long elapsed = System.nanoTime() - start;
            long sleepMillis = (frameTimeNanos - elapsed) / 1_000_000L;
            if (sleepMillis > 1) {
                try {
                    Thread.sleep(sleepMillis);
                } catch (InterruptedException e) {
                    break;
                }
            }
        }
    }

    private int[] scaleBuffer;
    private int lastDrawW = 0;
    private int lastDrawH = 0;

    @Override
    protected void paint(Graphics g) {
        int w = getWidth();
        int h = getHeight();

        // Background fill
        g.setColor(0x000000);
        g.fillRect(0, 0, w, h);

        // Draw NES buffer (256x240)
        if (w == 256 && h == 240) {
            g.drawRGB(ppu.screen, 0, 256, 0, 0, 256, 240, false);
        } else {
            int scale = Math.max(1, Math.min(w / 256, h / 240));
            int drawW = 256 * scale;
            int drawH = 240 * scale;
            int drawX = (w - drawW) / 2;
            int drawY = (h - drawH) / 2;

            if (scale == 1) {
                g.drawRGB(ppu.screen, 0, 256, drawX, drawY, 256, 240, false);
            } else {
                if (scaleBuffer == null || drawW != lastDrawW || drawH != lastDrawH) {
                    scaleBuffer = new int[drawW * drawH];
                    lastDrawW = drawW;
                    lastDrawH = drawH;
                }
                for (int y = 0; y < drawH; y++) {
                    int srcRow = (y / scale) * 256;
                    int dstRow = y * drawW;
                    for (int x = 0; x < drawW; x++) {
                        scaleBuffer[dstRow + x] = ppu.screen[srcRow + (x / scale)];
                    }
                }
                g.drawRGB(scaleBuffer, 0, drawW, drawX, drawY, drawW, drawH, false);
            }
        }
    }

    private void updateKey(int keyCode, boolean pressed) {
        int mask = 0;
        switch (keyCode) {
            case Canvas.KEY_UP, Canvas.KEY_NUM2 -> mask = MASK_UP;
            case Canvas.KEY_DOWN, Canvas.KEY_NUM8 -> mask = MASK_DOWN;
            case Canvas.KEY_LEFT, Canvas.KEY_NUM4 -> mask = MASK_LEFT;
            case Canvas.KEY_RIGHT, Canvas.KEY_NUM6 -> mask = MASK_RIGHT;
            case Canvas.KEY_NUM9, Canvas.KEY_FIRE, -21 -> mask = MASK_A; // Button A
            case Canvas.KEY_NUM7, -22 -> mask = MASK_B;                  // Button B
            case Canvas.KEY_STAR, Canvas.KEY_SOFT_LEFT -> mask = MASK_SELECT; // Select
            case Canvas.KEY_POUND, Canvas.KEY_SOFT_RIGHT -> mask = MASK_START; // Start
        }
        if (pressed) {
            joypad |= mask;
        } else {
            joypad &= ~mask;
        }
    }

    @Override
    protected void keyPressed(int keyCode) {
        updateKey(keyCode, true);
    }

    @Override
    protected void keyReleased(int keyCode) {
        updateKey(keyCode, false);
    }
}
