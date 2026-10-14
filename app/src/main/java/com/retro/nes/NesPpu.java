package com.retro.nes;

import java.util.Arrays;

public class NesPpu {
    public static final int WIDTH = 256;
    public static final int HEIGHT = 240;

    public final int[] screen = new int[WIDTH * HEIGHT];
    public final byte[] nameTables = new byte[2048]; // 2KB CIRAM for 2 nametables
    public final byte[] paletteRam = new byte[32];
    public final byte[] oam = new byte[256];

    public NesCartridge cart;
    public boolean nmiTriggered = false;

    // Registers
    public int ppuCtrl = 0;   // $2000
    public int ppuMask = 0;   // $2001
    public int ppuStatus = 0; // $2002
    public int oamAddr = 0;   // $2003

    // Scrolling registers
    public int v = 0; // Current VRAM address (15 bits)
    public int t = 0; // Temporary VRAM address (15 bits)
    public int fineX = 0; // Fine X scroll (3 bits)
    public boolean w = false; // First or second write toggle
    private int readBuffer = 0;

    public int scanline = 0;
    public int cycle = 0;
    public boolean frameComplete = false;

    // Classic 64-color NES palette in 0xAARRGGBB format
    public static final int[] NES_PALETTE = {
        0xFF666666, 0xFF002A88, 0xFF1412A7, 0xFF3B00A4, 0xFF5C007E, 0xFF6E0040, 0xFF6C0600, 0xFF561D00,
        0xFF333500, 0xFF0B4800, 0xFF005200, 0xFF004F08, 0xFF00404D, 0xFF000000, 0xFF000000, 0xFF000000,
        0xFFADADAD, 0xFF155FD9, 0xFF4240FF, 0xFF7527FE, 0xFFA01ACC, 0xFFB71E7B, 0xFFB53120, 0xFF994E00,
        0xFF6B6D00, 0xFF388700, 0xFF0C9300, 0xFF008F32, 0xFF007C8D, 0xFF000000, 0xFF000000, 0xFF000000,
        0xFFFFFEFF, 0xFF64B0FF, 0xFF9290FF, 0xFFC676FF, 0xFFF36AFF, 0xFFFE6ECC, 0xFFFE8170, 0xFFEA9E22,
        0xFFBCBE00, 0xFF88D800, 0xFF5CE430, 0xFF45E082, 0xFF48CDDE, 0xFF4F4F4F, 0xFF000000, 0xFF000000,
        0xFFFFFEFF, 0xFFC0DFFF, 0xFFD3D2FF, 0xFFE8C8FF, 0xFFFBC2FF, 0xFFFEC4EA, 0xFFFECCC5, 0xFFF7D8A5,
        0xFFE4E594, 0xFFCFEF96, 0xFFBDF4AB, 0xFFB3F3CC, 0xFFB5EBF2, 0xFFB8B8B8, 0xFF000000, 0xFF000000
    };

    public NesPpu(NesCartridge cart) {
        this.cart = cart;
        Arrays.fill(screen, 0xFF000000);
    }

    public int readRegister(int reg) {
        reg &= 7;
        switch (reg) {
            case 2 -> { // PPUSTATUS
                int res = (ppuStatus & 0xE0) | (readBuffer & 0x1F);
                ppuStatus &= ~0x80; // Clear VBlank flag
                w = false;
                return res;
            }
            case 4 -> { // OAMDATA
                return oam[oamAddr & 0xFF] & 0xFF;
            }
            case 7 -> { // PPUDATA
                int res = readBuffer;
                readBuffer = readVram(v);
                if (v >= 0x3F00) {
                    res = readBuffer;
                }
                v = (v + ((ppuCtrl & 4) != 0 ? 32 : 1)) & 0x7FFF;
                return res;
            }
        }
        return 0;
    }

    public void writeRegister(int reg, int val) {
        val &= 0xFF;
        reg &= 7;
        switch (reg) {
            case 0 -> { // PPUCTRL
                boolean wasNmi = (ppuCtrl & 0x80) != 0;
                ppuCtrl = val;
                t = (t & ~0x0C00) | ((val & 3) << 10);
                if (!wasNmi && (ppuCtrl & 0x80) != 0 && (ppuStatus & 0x80) != 0) {
                    nmiTriggered = true;
                }
            }
            case 1 -> ppuMask = val; // PPUMASK
            case 3 -> oamAddr = val; // OAMADDR
            case 4 -> { // OAMDATA
                oam[oamAddr & 0xFF] = (byte) val;
                oamAddr = (oamAddr + 1) & 0xFF;
            }
            case 5 -> { // PPUSCROLL
                if (!w) {
                    t = (t & ~0x001F) | ((val >> 3) & 0x1F);
                    fineX = val & 7;
                    w = true;
                } else {
                    t = (t & ~0x73E0) | ((val & 7) << 12) | ((val & 0xF8) << 2);
                    w = false;
                }
            }
            case 6 -> { // PPUADDR
                if (!w) {
                    t = (t & 0x00FF) | ((val & 0x3F) << 8);
                    w = true;
                } else {
                    t = (t & 0xFF00) | val;
                    v = t;
                    w = false;
                }
            }
            case 7 -> { // PPUDATA
                writeVram(v, val);
                v = (v + ((ppuCtrl & 4) != 0 ? 32 : 1)) & 0x7FFF;
            }
        }
    }

    private int readVram(int addr) {
        addr &= 0x3FFF;
        if (addr < 0x2000) {
            return cart.readChr(addr);
        } else if (addr < 0x3F00) {
            return nameTables[mirrorAddress(addr)] & 0xFF;
        } else {
            int p = addr & 0x1F;
            if (p == 0x10 || p == 0x14 || p == 0x18 || p == 0x1C) p -= 0x10;
            return paletteRam[p] & 0xFF;
        }
    }

    private void writeVram(int addr, int val) {
        addr &= 0x3FFF;
        if (addr < 0x2000) {
            cart.writeChr(addr, val);
        } else if (addr < 0x3F00) {
            nameTables[mirrorAddress(addr)] = (byte) val;
        } else {
            int p = addr & 0x1F;
            if (p == 0x10 || p == 0x14 || p == 0x18 || p == 0x1C) p -= 0x10;
            paletteRam[p] = (byte) val;
        }
    }

    private int mirrorAddress(int addr) {
        addr = (addr - 0x2000) & 0x0FFF;
        int table = addr / 0x0400;
        int offset = addr % 0x0400;
        if (cart.mirrorVertical) {
            return ((table & 1) * 0x0400) + offset;
        } else {
            return ((table >> 1) * 0x0400) + offset;
        }
    }

    public void renderScanline(int sl) {
        if (sl < 0 || sl >= HEIGHT) return;
        boolean showBg = (ppuMask & 0x08) != 0;
        boolean showSpr = (ppuMask & 0x10) != 0;

        int rowOffset = sl * WIDTH;
        int universalBg = NES_PALETTE[paletteRam[0] & 0x3F];
        Arrays.fill(screen, rowOffset, rowOffset + WIDTH, universalBg);

        int[] bgPixels = new int[WIDTH];
        int bgTable = (ppuCtrl & 0x10) != 0 ? 0x1000 : 0;

        if (showBg) {
            int coarseX = (v & 0x001F);
            int coarseY = (v >> 5) & 0x001F;
            int nt = (v >> 10) & 3;
            int fineY = (v >> 12) & 7;

            for (int tile = 0; tile < 33; tile++) {
                int curCoarseX = (coarseX + tile) % 32;
                int curNt = nt ^ (((coarseX + tile) >= 32) ? 1 : 0);

                int ntAddr = 0x2000 + (curNt * 0x0400) + (coarseY * 32) + curCoarseX;
                int tileId = readVram(ntAddr);

                // Attribute table
                int attrAddr = 0x23C0 + (curNt * 0x0400) + ((coarseY / 4) * 8) + (curCoarseX / 4);
                int attr = readVram(attrAddr);
                int shift = ((coarseY & 2) != 0 ? 4 : 0) | ((curCoarseX & 2) != 0 ? 2 : 0);
                int pal = (attr >> shift) & 3;

                // Pattern table tile
                int patternAddr = bgTable + (tileId * 16) + fineY;
                int lo = readVram(patternAddr);
                int hi = readVram(patternAddr + 8);

                for (int bit = 7; bit >= 0; bit--) {
                    int pixelX = (tile * 8) + (7 - bit) - fineX;
                    if (pixelX >= 0 && pixelX < WIDTH) {
                        int colorIndex = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1);
                        bgPixels[pixelX] = colorIndex;
                        if (colorIndex != 0) {
                            int palEntry = readVram(0x3F00 + (pal * 4) + colorIndex) & 0x3F;
                            screen[rowOffset + pixelX] = NES_PALETTE[palEntry];
                        }
                    }
                }
            }
        }

        if (showSpr) {
            int sprTable = (ppuCtrl & 0x08) != 0 ? 0x1000 : 0;
            boolean is8x16 = (ppuCtrl & 0x20) != 0;
            int sprHeight = is8x16 ? 16 : 8;

            for (int i = 63; i >= 0; i--) {
                int oamIdx = i * 4;
                int sprY = (oam[oamIdx] & 0xFF) + 1;
                int tile = oam[oamIdx + 1] & 0xFF;
                int attr = oam[oamIdx + 2] & 0xFF;
                int sprX = oam[oamIdx + 3] & 0xFF;

                if (sl >= sprY && sl < (sprY + sprHeight)) {
                    int line = sl - sprY;
                    boolean flipV = (attr & 0x80) != 0;
                    boolean flipH = (attr & 0x40) != 0;
                    boolean priority = (attr & 0x20) == 0; // 0 = in front of BG
                    int pal = (attr & 3) + 4;

                    if (flipV) line = sprHeight - 1 - line;

                    int patternAddr;
                    if (is8x16) {
                        int table = (tile & 1) * 0x1000;
                        int tIndex = tile & 0xFE;
                        if (line >= 8) {
                            tIndex++;
                            line -= 8;
                        }
                        patternAddr = table + (tIndex * 16) + line;
                    } else {
                        patternAddr = sprTable + (tile * 16) + line;
                    }

                    int lo = readVram(patternAddr);
                    int hi = readVram(patternAddr + 8);

                    for (int bit = 7; bit >= 0; bit--) {
                        int col = flipH ? (7 - bit) : bit;
                        int pixelX = sprX + (7 - bit);
                        if (pixelX >= 0 && pixelX < WIDTH) {
                            int colorIndex = ((lo >> col) & 1) | (((hi >> col) & 1) << 1);
                            if (colorIndex != 0) {
                                // Sprite 0 hit check
                                if (i == 0 && bgPixels[pixelX] != 0 && pixelX != 255) {
                                    ppuStatus |= 0x40;
                                }
                                if (priority || bgPixels[pixelX] == 0) {
                                    int palEntry = readVram(0x3F00 + (pal * 4) + colorIndex) & 0x3F;
                                    screen[rowOffset + pixelX] = NES_PALETTE[palEntry];
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public void stepScanline() {
        if (scanline < 240) {
            renderScanline(scanline);
            cart.clockScanline();
        } else if (scanline == 241) {
            ppuStatus |= 0x80; // Set VBlank
            if ((ppuCtrl & 0x80) != 0) {
                nmiTriggered = true;
            }
            frameComplete = true;
        } else if (scanline == 261) {
            ppuStatus &= ~(0x80 | 0x40 | 0x20); // Clear VBlank, Sprite 0 hit, Sprite overflow
        }

        scanline++;
        if (scanline >= 262) {
            scanline = 0;
        }
    }
}
