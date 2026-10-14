package com.retro.snes;

import java.io.InputStream;
import javax.microedition.lcdui.Canvas;
import javax.microedition.lcdui.Graphics;

public class SnesCanvas extends Canvas implements Runnable {
    private final SnesCartridge cart;
    private final SnesPpu ppu;
    private final SnesCpu cpu;
    private Thread emuThread;
    private volatile boolean running = false;

    // SNES Joypad bits: B(15), Y(14), Select(13), Start(12), Up(11), Down(10), Left(9), Right(8), A(7), X(6), L(5), R(4)
    private static final int BTN_B      = 1 << 15;
    private static final int BTN_Y      = 1 << 14;
    private static final int BTN_SELECT = 1 << 13;
    private static final int BTN_START  = 1 << 12;
    private static final int BTN_UP     = 1 << 11;
    private static final int BTN_DOWN   = 1 << 10;
    private static final int BTN_LEFT   = 1 << 9;
    private static final int BTN_RIGHT  = 1 << 8;
    private static final int BTN_A      = 1 << 7;
    private static final int BTN_X      = 1 << 6;
    private static final int BTN_L      = 1 << 5;
    private static final int BTN_R      = 1 << 4;

    private int joypad = 0;

    public SnesCanvas(InputStream romStream) throws Exception {
        cart = SnesCartridge.load(romStream);
        ppu = new SnesPpu();
        cpu = new SnesCpu(ppu, cart);
    }

    public void start() {
        if (running) return;
        running = true;
        emuThread = new Thread(this, "SNES-Emulator");
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
            cpu.joy1 = joypad;
            for (int sl = 0; sl < 262; sl++) {
                ppu.stepScanline();
                // ~350 CPU cycles per scanline
                int cyclesTarget = 350;
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

    @Override
    protected void paint(Graphics g) {
        int w = getWidth();
        int h = getHeight();

        g.setColor(0x000000);
        g.fillRect(0, 0, w, h);

        // Draw SNES frame buffer (256x224)
        if (w == 256 && h == 224) {
            g.drawRGB(ppu.screen, 0, 256, 0, 0, 256, 224, false);
        } else {
            int scale = Math.max(1, Math.min(w / 256, h / 224));
            int drawW = 256 * scale;
            int drawH = 224 * scale;
            int drawX = (w - drawW) / 2;
            int drawY = (h - drawH) / 2;

            if (scale == 1) {
                g.drawRGB(ppu.screen, 0, 256, drawX, drawY, 256, 224, false);
            } else {
                int[] scaled = new int[drawW * drawH];
                for (int y = 0; y < drawH; y++) {
                    int srcY = y / scale;
                    int srcRow = srcY * 256;
                    int dstRow = y * drawW;
                    for (int x = 0; x < drawW; x++) {
                        scaled[dstRow + x] = ppu.screen[srcRow + (x / scale)];
                    }
                }
                g.drawRGB(scaled, 0, drawW, drawX, drawY, drawW, drawH, false);
            }
        }
    }

    private void updateKey(int keyCode, boolean pressed) {
        int mask = 0;
        switch (keyCode) {
            case Canvas.KEY_UP, Canvas.KEY_NUM2 -> mask = BTN_UP;
            case Canvas.KEY_DOWN, Canvas.KEY_NUM8 -> mask = BTN_DOWN;
            case Canvas.KEY_LEFT, Canvas.KEY_NUM4 -> mask = BTN_LEFT;
            case Canvas.KEY_RIGHT, Canvas.KEY_NUM6 -> mask = BTN_RIGHT;
            case Canvas.KEY_FIRE, Canvas.KEY_NUM9, -21 -> mask = BTN_A; // Button A
            case Canvas.KEY_NUM7, -22 -> mask = BTN_B;                  // Button B
            case Canvas.KEY_END -> mask = BTN_X;                        // Button X (C key)
            case Canvas.KEY_SEND -> mask = BTN_Y;                       // Button Y (D key)
            case Canvas.KEY_SOFT_LEFT, Canvas.KEY_NUM1 -> mask = BTN_L; // Shoulder L
            case Canvas.KEY_SOFT_RIGHT, Canvas.KEY_NUM3 -> mask = BTN_R;// Shoulder R
            case Canvas.KEY_STAR -> mask = BTN_SELECT;                  // Select
            case Canvas.KEY_POUND -> mask = BTN_START;                  // Start
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
