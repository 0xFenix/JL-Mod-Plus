package com.retro.nes;

import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

public class NesCartridge {
    public byte[] prgRom;
    public byte[] chrRom;
    public byte[] prgRam = new byte[0x2000];
    public int mapper;
    public boolean mirrorVertical; // true = vertical, false = horizontal
    public boolean fourScreen;

    // MMC1 state
    private int mmc1Shift = 0x10;
    private int mmc1Control = 0x0C;
    private int mmc1PrgBank = 0;
    private int mmc1ChrBank0 = 0;
    private int mmc1ChrBank1 = 0;

    // UNROM (Mapper 2) & CNROM (Mapper 3)
    private int prgBank0 = 0;
    private int chrBank0 = 0;

    // MMC3 state (Mapper 4)
    private int[] mmc3Regs = new int[8];
    private int mmc3BankSelect = 0;
    public boolean irqEnabled = false;
    public int irqLatch = 0;
    public int irqCounter = 0;
    public boolean irqPending = false;

    public static NesCartridge load(InputStream in) throws IOException {
        byte[] header = new byte[16];
        int read = in.read(header);
        if (read < 16 || header[0] != 'N' || header[1] != 'E' || header[2] != 'S' || header[3] != 0x1A) {
            throw new IOException("Invalid iNES ROM header");
        }

        NesCartridge cart = new NesCartridge();
        int prgBanks = header[4] & 0xFF;
        int chrBanks = header[5] & 0xFF;
        int flag6 = header[6] & 0xFF;
        int flag7 = header[7] & 0xFF;

        cart.mirrorVertical = (flag6 & 1) != 0;
        cart.fourScreen = (flag6 & 8) != 0;
        cart.mapper = (flag6 >> 4) | (flag7 & 0xF0);

        if ((flag6 & 4) != 0) { // Trainer present (512 bytes)
            byte[] trainer = new byte[512];
            in.read(trainer);
        }

        cart.prgRom = new byte[prgBanks * 16384];
        readFully(in, cart.prgRom);

        if (chrBanks > 0) {
            cart.chrRom = new byte[chrBanks * 8192];
            readFully(in, cart.chrRom);
        } else {
            cart.chrRom = new byte[8192]; // CHR RAM
        }

        return cart;
    }

    private static void readFully(InputStream in, byte[] buffer) throws IOException {
        int offset = 0;
        while (offset < buffer.length) {
            int count = in.read(buffer, offset, buffer.length - offset);
            if (count < 0) throw new IOException("Unexpected EOF in ROM");
            offset += count;
        }
    }

    public int readPrg(int addr) {
        if (addr >= 0x6000 && addr < 0x8000) {
            return prgRam[addr - 0x6000] & 0xFF;
        }
        if (addr >= 0x8000) {
            addr -= 0x8000;
            switch (mapper) {
                case 0: // NROM
                    if (prgRom.length == 16384) addr &= 0x3FFF;
                    return prgRom[addr % prgRom.length] & 0xFF;

                case 1: { // MMC1
                    int bankMode = (mmc1Control >> 2) & 3;
                    int num16k = prgRom.length / 16384;
                    if (bankMode == 0 || bankMode == 1) { // 32k mode
                        int bank = (mmc1PrgBank & ~1) % (num16k > 0 ? num16k : 1);
                        return prgRom[(bank * 16384 + addr) % prgRom.length] & 0xFF;
                    } else if (bankMode == 2) { // Fix first, switch second
                        if (addr < 0x4000) {
                            return prgRom[addr] & 0xFF;
                        } else {
                            int bank = mmc1PrgBank % (num16k > 0 ? num16k : 1);
                            return prgRom[(bank * 16384 + (addr - 0x4000)) % prgRom.length] & 0xFF;
                        }
                    } else { // Switch first, fix last
                        if (addr < 0x4000) {
                            int bank = mmc1PrgBank % (num16k > 0 ? num16k : 1);
                            return prgRom[(bank * 16384 + addr) % prgRom.length] & 0xFF;
                        } else {
                            int last = (num16k - 1) * 16384;
                            return prgRom[(last + (addr - 0x4000)) % prgRom.length] & 0xFF;
                        }
                    }
                }

                case 2: { // UNROM
                    int num16k = prgRom.length / 16384;
                    if (addr < 0x4000) {
                        int bank = prgBank0 % (num16k > 0 ? num16k : 1);
                        return prgRom[(bank * 16384 + addr) % prgRom.length] & 0xFF;
                    } else {
                        int last = (num16k - 1) * 16384;
                        return prgRom[(last + (addr - 0x4000)) % prgRom.length] & 0xFF;
                    }
                }

                case 3: // CNROM
                    return prgRom[addr % prgRom.length] & 0xFF;

                case 4: { // MMC3
                    int num8k = prgRom.length / 8192;
                    int bankMode = (mmc3BankSelect >> 6) & 1;
                    int bank = 0;
                    if (addr < 0x2000) {
                        bank = (bankMode == 0) ? mmc3Regs[6] : (num8k - 2);
                    } else if (addr < 0x4000) {
                        bank = mmc3Regs[7];
                    } else if (addr < 0x6000) {
                        bank = (bankMode == 0) ? (num8k - 2) : mmc3Regs[6];
                    } else {
                        bank = num8k - 1;
                    }
                    int offset = (bank % (num8k > 0 ? num8k : 1)) * 8192 + (addr & 0x1FFF);
                    return prgRom[offset % prgRom.length] & 0xFF;
                }

                default:
                    return prgRom[addr % prgRom.length] & 0xFF;
            }
        }
        return 0;
    }

    public void writePrg(int addr, int val) {
        if (addr >= 0x6000 && addr < 0x8000) {
            prgRam[addr - 0x6000] = (byte) val;
            return;
        }
        if (addr >= 0x8000) {
            switch (mapper) {
                case 1: { // MMC1
                    if ((val & 0x80) != 0) {
                        mmc1Shift = 0x10;
                        mmc1Control |= 0x0C;
                    } else {
                        boolean complete = (mmc1Shift & 1) != 0;
                        mmc1Shift = (mmc1Shift >> 1) | ((val & 1) << 4);
                        if (complete) {
                            int reg = (addr >> 13) & 3;
                            switch (reg) {
                                case 0 -> {
                                    mmc1Control = mmc1Shift;
                                    int m = mmc1Control & 3;
                                    mirrorVertical = (m == 3);
                                }
                                case 1 -> mmc1ChrBank0 = mmc1Shift;
                                case 2 -> mmc1ChrBank1 = mmc1Shift;
                                case 3 -> mmc1PrgBank = mmc1Shift & 0x0F;
                            }
                            mmc1Shift = 0x10;
                        }
                    }
                    break;
                }
                case 2: // UNROM
                    prgBank0 = val & 0x0F;
                    break;
                case 3: // CNROM
                    chrBank0 = val & 0x03;
                    break;
                case 4: { // MMC3
                    int reg = addr & 0xE001;
                    switch (reg) {
                        case 0x8000 -> mmc3BankSelect = val;
                        case 0x8001 -> {
                            int target = mmc3BankSelect & 7;
                            mmc3Regs[target] = val;
                        }
                        case 0xA000 -> mirrorVertical = (val & 1) == 0;
                        case 0xC000 -> irqLatch = val;
                        case 0xC001 -> irqCounter = 0;
                        case 0xE000 -> {
                            irqEnabled = false;
                            irqPending = false;
                        }
                        case 0xE001 -> irqEnabled = true;
                    }
                    break;
                }
            }
        }
    }

    public int readChr(int addr) {
        if (chrRom == null || chrRom.length == 0) return 0;
        addr &= 0x1FFF;
        switch (mapper) {
            case 1: { // MMC1
                int chrMode = (mmc1Control >> 4) & 1;
                int num4k = chrRom.length / 4096;
                if (chrMode == 0) { // 8k mode
                    int bank = (mmc1ChrBank0 & ~1) % (num4k > 0 ? num4k : 1);
                    return chrRom[(bank * 4096 + addr) % chrRom.length] & 0xFF;
                } else { // 4k mode
                    if (addr < 0x1000) {
                        int bank = mmc1ChrBank0 % (num4k > 0 ? num4k : 1);
                        return chrRom[(bank * 4096 + addr) % chrRom.length] & 0xFF;
                    } else {
                        int bank = mmc1ChrBank1 % (num4k > 0 ? num4k : 1);
                        return chrRom[(bank * 4096 + (addr - 0x1000)) % chrRom.length] & 0xFF;
                    }
                }
            }
            case 3: { // CNROM
                int num8k = chrRom.length / 8192;
                int bank = chrBank0 % (num8k > 0 ? num8k : 1);
                return chrRom[(bank * 8192 + addr) % chrRom.length] & 0xFF;
            }
            case 4: { // MMC3
                int num1k = chrRom.length / 1024;
                int chrA12 = (mmc3BankSelect >> 7) & 1;
                int bank = 0;
                if (chrA12 == 0) {
                    if (addr < 0x0800) bank = (mmc3Regs[0] & ~1) + (addr / 1024);
                    else if (addr < 0x1000) bank = (mmc3Regs[1] & ~1) + ((addr - 0x0800) / 1024);
                    else if (addr < 0x1400) bank = mmc3Regs[2];
                    else if (addr < 0x1800) bank = mmc3Regs[3];
                    else if (addr < 0x1C00) bank = mmc3Regs[4];
                    else bank = mmc3Regs[5];
                } else {
                    if (addr < 0x0400) bank = mmc3Regs[2];
                    else if (addr < 0x0800) bank = mmc3Regs[3];
                    else if (addr < 0x0C00) bank = mmc3Regs[4];
                    else if (addr < 0x1000) bank = mmc3Regs[5];
                    else if (addr < 0x1800) bank = (mmc3Regs[0] & ~1) + ((addr - 0x1000) / 1024);
                    else bank = (mmc3Regs[1] & ~1) + ((addr - 0x1800) / 1024);
                }
                int offset = (bank % (num1k > 0 ? num1k : 1)) * 1024 + (addr & 0x03FF);
                return chrRom[offset % chrRom.length] & 0xFF;
            }
            default:
                return chrRom[addr % chrRom.length] & 0xFF;
        }
    }

    public void writeChr(int addr, int val) {
        if (chrRom != null && chrRom.length == 8192 && mapper == 0) {
            chrRom[addr & 0x1FFF] = (byte) val; // CHR RAM write
        }
    }

    public void clockScanline() {
        if (mapper == 4) { // MMC3 scanline IRQ
            if (irqCounter == 0) {
                irqCounter = irqLatch;
            } else {
                irqCounter--;
            }
            if (irqCounter == 0 && irqEnabled) {
                irqPending = true;
            }
        }
    }
}
