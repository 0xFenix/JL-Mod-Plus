package com.retro.snes;

import java.util.Arrays;

public class SnesPpu {
    public static final int WIDTH = 256;
    public static final int HEIGHT = 224;

    public final int[] screen = new int[WIDTH * HEIGHT];
    public final byte[] vram = new byte[65536];
    public final byte[] cgram = new byte[512]; // 256 colors * 2 bytes
    public final byte[] oam = new byte[544];

    public int inidisp = 0x0F;
    public int obsel = 0;
    public int oamAddr = 0;
    public int bgMode = 0;
    public int[] bgSc = new int[4];
    public int[] bgNba = new int[4];
    public int[] bgHofs = new int[4];
    public int[] bgVofs = new int[4];
    private int vmain = 0;
    public int vmAddr = 0;
    public int cgAddr = 0;
    private boolean cgFlip = false;
    private int vramReadBuf = 0;

    public int scanline = 0;
    public boolean nmiTriggered = false;
    public boolean frameComplete = false;

    // Converted 256 ARGB colors from CGRAM
    private final int[] paletteRgb = new int[256];

    public SnesPpu() {
        Arrays.fill(screen, 0xFF000000);
        Arrays.fill(paletteRgb, 0xFF000000);
    }

    public void writeRegister(int addr, int val) {
        addr &= 0xFF;
        val &= 0xFF;
        switch (addr) {
            case 0x00 -> inidisp = val;
            case 0x01 -> obsel = val;
            case 0x02 -> oamAddr = (oamAddr & 0x0100) | val;
            case 0x03 -> oamAddr = (oamAddr & 0x00FF) | ((val & 1) << 8);
            case 0x04 -> {
                oam[oamAddr & 0x1FF] = (byte) val;
                oamAddr = (oamAddr + 1) & 0x1FF;
            }
            case 0x05 -> bgMode = val;
            case 0x07 -> bgSc[0] = val;
            case 0x08 -> bgSc[1] = val;
            case 0x09 -> bgSc[2] = val;
            case 0x0A -> bgSc[3] = val;
            case 0x0B -> {
                bgNba[0] = val & 0x0F;
                bgNba[1] = (val >> 4) & 0x0F;
            }
            case 0x0C -> {
                bgNba[2] = val & 0x0F;
                bgNba[3] = (val >> 4) & 0x0F;
            }
            case 0x0D -> bgHofs[0] = val;
            case 0x0E -> bgVofs[0] = val;
            case 0x0F -> bgHofs[1] = val;
            case 0x10 -> bgVofs[1] = val;
            case 0x11 -> bgHofs[2] = val;
            case 0x12 -> bgVofs[2] = val;
            case 0x13 -> bgHofs[3] = val;
            case 0x14 -> bgVofs[3] = val;
            case 0x15 -> vmain = val;
            case 0x16 -> vmAddr = (vmAddr & 0xFF00) | val;
            case 0x17 -> vmAddr = (vmAddr & 0x00FF) | (val << 8);
            case 0x18 -> { // VMDATAL
                int byteAddr = (vmAddr & 0x7FFF) << 1;
                vram[byteAddr] = (byte) val;
                if ((vmain & 0x80) == 0) stepVmAddr();
            }
            case 0x19 -> { // VMDATAH
                int byteAddr = ((vmAddr & 0x7FFF) << 1) + 1;
                vram[byteAddr] = (byte) val;
                if ((vmain & 0x80) != 0) stepVmAddr();
            }
            case 0x21 -> {
                cgAddr = val;
                cgFlip = false;
            }
            case 0x22 -> { // CGDATA
                int idx = (cgAddr & 0xFF) * 2 + (cgFlip ? 1 : 0);
                cgram[idx] = (byte) val;
                if (cgFlip) {
                    updatePalette(cgAddr & 0xFF);
                    cgAddr = (cgAddr + 1) & 0xFF;
                }
                cgFlip = !cgFlip;
            }
        }
    }

    private void stepVmAddr() {
        int inc = switch (vmain & 3) {
            case 1 -> 32;
            case 2 -> 128;
            case 3 -> 128;
            default -> 1;
        };
        vmAddr = (vmAddr + inc) & 0xFFFF;
    }

    private void updatePalette(int index) {
        int lo = cgram[index * 2] & 0xFF;
        int hi = cgram[index * 2 + 1] & 0xFF;
        int bgr555 = lo | (hi << 8);
        int r = (bgr555 & 0x1F) << 3;
        int g = ((bgr555 >> 5) & 0x1F) << 3;
        int b = ((bgr555 >> 10) & 0x1F) << 3;
        paletteRgb[index] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    public int readRegister(int addr) {
        addr &= 0xFF;
        switch (addr) {
            case 0x34 -> { return 0; }
            case 0x39 -> { // VMDATALREAD
                int res = vramReadBuf & 0xFF;
                int byteAddr = (vmAddr & 0x7FFF) << 1;
                vramReadBuf = (vram[byteAddr] & 0xFF) | ((vram[byteAddr + 1] & 0xFF) << 8);
                if ((vmain & 0x80) == 0) stepVmAddr();
                return res;
            }
            case 0x3A -> { // VMDATAHREAD
                int res = (vramReadBuf >> 8) & 0xFF;
                int byteAddr = (vmAddr & 0x7FFF) << 1;
                vramReadBuf = (vram[byteAddr] & 0xFF) | ((vram[byteAddr + 1] & 0xFF) << 8);
                if ((vmain & 0x80) != 0) stepVmAddr();
                return res;
            }
            case 0x3E -> { return 0x01; } // STAT77
            case 0x3F -> { return (scanline >= 225 ? 0x80 : 0) | 0x01; } // STAT78
        }
        return 0;
    }

    public void renderScanline(int sl) {
        if (sl < 0 || sl >= HEIGHT) return;
        int rowOffset = sl * WIDTH;

        // Forced blank
        if ((inidisp & 0x80) != 0) {
            Arrays.fill(screen, rowOffset, rowOffset + WIDTH, 0xFF000000);
            return;
        }

        int backdrop = paletteRgb[0];
        Arrays.fill(screen, rowOffset, rowOffset + WIDTH, backdrop);

        // Render BG1 (Layer 1)
        int scBase = (bgSc[0] & 0xFC) << 9; // Tilemap address in bytes
        int charBase = (bgNba[0] & 0x0F) << 13; // Character tile address in bytes
        int hScroll = bgHofs[0] & 0x3FF;
        int vScroll = bgVofs[0] & 0x3FF;

        int tileY = (sl + vScroll) / 8;
        int fineY = (sl + vScroll) % 8;

        for (int x = 0; x < WIDTH; x++) {
            int tileX = (x + hScroll) / 8;
            int fineX = (x + hScroll) % 8;

            int mapAddr = scBase + ((tileY & 31) * 32 + (tileX & 31)) * 2;
            if (mapAddr + 1 < vram.length) {
                int tileWord = (vram[mapAddr] & 0xFF) | ((vram[mapAddr + 1] & 0xFF) << 8);
                int tileNum = tileWord & 0x3FF;
                int pal = (tileWord >> 10) & 7;
                boolean flipH = (tileWord & 0x4000) != 0;
                boolean flipV = (tileWord & 0x8000) != 0;

                int py = flipV ? (7 - fineY) : fineY;
                int px = flipH ? (7 - fineX) : fineX;

                // 4bpp tile decoding (Mode 1 / 2)
                int tileAddr = charBase + (tileNum * 32) + (py * 2);
                if (tileAddr + 17 < vram.length) {
                    int b0 = vram[tileAddr] & 0xFF;
                    int b1 = vram[tileAddr + 1] & 0xFF;
                    int b2 = vram[tileAddr + 16] & 0xFF;
                    int b3 = vram[tileAddr + 17] & 0xFF;

                    int bit = 7 - px;
                    int color = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1) |
                                (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3);

                    if (color != 0) {
                        int palIdx = (pal * 16) + color;
                        screen[rowOffset + x] = paletteRgb[palIdx & 0xFF];
                    }
                }
            }
        }

        // Render Sprites (OAM)
        for (int i = 127; i >= 0; i--) {
            int entry = i * 4;
            int sprX = oam[entry] & 0xFF;
            int sprY = (oam[entry + 1] & 0xFF);
            int tile = oam[entry + 2] & 0xFF;
            int attr = oam[entry + 3] & 0xFF;

            int sprHeight = 8;
            if (sl >= sprY && sl < (sprY + sprHeight)) {
                int line = sl - sprY;
                boolean flipV = (attr & 0x80) != 0;
                boolean flipH = (attr & 0x40) != 0;
                int pal = 128 + ((attr >> 1) & 7) * 16;

                if (flipV) line = 7 - line;
                int tileAddr = ((obsel & 7) << 14) + (tile * 32) + (line * 2);

                if (tileAddr + 17 < vram.length) {
                    int b0 = vram[tileAddr] & 0xFF;
                    int b1 = vram[tileAddr + 1] & 0xFF;
                    int b2 = vram[tileAddr + 16] & 0xFF;
                    int b3 = vram[tileAddr + 17] & 0xFF;

                    for (int bit = 7; bit >= 0; bit--) {
                        int px = flipH ? (7 - bit) : bit;
                        int drawX = sprX + (7 - bit);
                        if (drawX >= 0 && drawX < WIDTH) {
                            int color = ((b0 >> px) & 1) | (((b1 >> px) & 1) << 1) |
                                        (((b2 >> px) & 1) << 2) | (((b3 >> px) & 1) << 3);
                            if (color != 0) {
                                screen[rowOffset + drawX] = paletteRgb[(pal + color) & 0xFF];
                            }
                        }
                    }
                }
            }
        }
    }

    public void stepScanline() {
        if (scanline < HEIGHT) {
            renderScanline(scanline);
        } else if (scanline == 225) {
            nmiTriggered = true;
            frameComplete = true;
        }

        scanline++;
        if (scanline >= 262) {
            scanline = 0;
        }
    }
}
