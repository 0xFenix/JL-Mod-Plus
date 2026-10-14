package com.retro.snes;

import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

public class SnesCartridge {
    public byte[] rom;
    public byte[] sram = new byte[0x8000]; // 32KB battery RAM
    public boolean isHiRom = false;
    public String title = "";

    public static SnesCartridge load(InputStream in) throws IOException {
        byte[] raw = in.readAllBytes();
        if (raw.length < 0x8000) {
            throw new IOException("SNES ROM too small: " + raw.length + " bytes");
        }

        int headerOffset = 0;
        // Check SMC header (512 bytes)
        if (raw.length % 1024 == 512) {
            headerOffset = 512;
        }

        SnesCartridge cart = new SnesCartridge();
        int romLength = raw.length - headerOffset;
        cart.rom = new byte[romLength];
        System.arraycopy(raw, headerOffset, cart.rom, 0, romLength);

        // Detect LoROM vs HiROM from internal header
        int scoreLo = scoreHeader(cart.rom, 0x7FC0);
        int scoreHi = scoreHeader(cart.rom, 0xFFC0);
        cart.isHiRom = (scoreHi > scoreLo);

        int headerBase = cart.isHiRom ? 0xFFC0 : 0x7FC0;
        if (headerBase + 32 <= cart.rom.length) {
            byte[] titleBytes = new byte[21];
            System.arraycopy(cart.rom, headerBase, titleBytes, 0, 21);
            cart.title = new String(titleBytes).trim();
        }

        return cart;
    }

    private static int scoreHeader(byte[] data, int addr) {
        if (addr + 32 > data.length) return -1;
        int score = 0;
        int resetVector = (data[addr + 0x3C] & 0xFF) | ((data[addr + 0x3D] & 0xFF) << 8);
        if (resetVector >= 0x8000) score += 2;
        int checksum = (data[addr + 0x1E] & 0xFF) | ((data[addr + 0x1F] & 0xFF) << 8);
        int checksumCompl = (data[addr + 0x1C] & 0xFF) | ((data[addr + 0x1D] & 0xFF) << 8);
        if ((checksum ^ checksumCompl) == 0xFFFF) score += 4;
        return score;
    }

    public int read(int bank, int addr) {
        bank &= 0xFF;
        addr &= 0xFFFF;

        if (isHiRom) {
            // HiROM mapping
            if (bank >= 0x40 && bank <= 0x7D) {
                int romAddr = ((bank - 0x40) << 16) | addr;
                return rom[romAddr % rom.length] & 0xFF;
            } else if (bank >= 0xC0) {
                int romAddr = ((bank - 0xC0) << 16) | addr;
                return rom[romAddr % rom.length] & 0xFF;
            } else if (addr >= 0x8000) {
                int romAddr = ((bank & 0x3F) << 16) | addr;
                return rom[romAddr % rom.length] & 0xFF;
            } else if (bank >= 0x20 && bank <= 0x3F && addr >= 0x6000 && addr < 0x8000) {
                int sramAddr = ((bank - 0x20) << 13) | (addr & 0x1FFF);
                return sram[sramAddr % sram.length] & 0xFF;
            }
        } else {
            // LoROM mapping
            if (addr >= 0x8000) {
                int romAddr = ((bank & 0x7F) << 15) | (addr & 0x7FFF);
                return rom[romAddr % rom.length] & 0xFF;
            } else if (bank >= 0x70 && bank <= 0x7D && addr < 0x8000) {
                int sramAddr = ((bank - 0x70) << 15) | addr;
                return sram[sramAddr % sram.length] & 0xFF;
            }
        }
        return 0;
    }

    public void write(int bank, int addr, int val) {
        bank &= 0xFF;
        addr &= 0xFFFF;
        val &= 0xFF;

        if (isHiRom) {
            if (bank >= 0x20 && bank <= 0x3F && addr >= 0x6000 && addr < 0x8000) {
                int sramAddr = ((bank - 0x20) << 13) | (addr & 0x1FFF);
                sram[sramAddr % sram.length] = (byte) val;
            }
        } else {
            if (bank >= 0x70 && bank <= 0x7D && addr < 0x8000) {
                int sramAddr = ((bank - 0x70) << 15) | addr;
                sram[sramAddr % sram.length] = (byte) val;
            }
        }
    }
}
