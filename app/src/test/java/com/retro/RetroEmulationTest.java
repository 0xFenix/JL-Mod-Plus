package com.retro;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import com.retro.nes.NesCanvas;
import com.retro.nes.NesCartridge;
import com.retro.nes.NesCpu;
import com.retro.nes.NesPpu;
import com.retro.snes.SnesCanvas;
import com.retro.snes.SnesCartridge;
import com.retro.snes.SnesCpu;
import com.retro.snes.SnesPpu;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.util.Arrays;

public class RetroEmulationTest {

    @Test
    public void nesEmulationInitializesAndStepsFrame() throws Exception {
        // Construct a minimal valid iNES ROM: 16 bytes header + 16KB PRG ROM + 8KB CHR ROM
        byte[] romBytes = new byte[16 + 16384 + 8192];
        romBytes[0] = 'N';
        romBytes[1] = 'E';
        romBytes[2] = 'S';
        romBytes[3] = 0x1A;
        romBytes[4] = 1; // 1 x 16KB PRG
        romBytes[5] = 1; // 1 x 8KB CHR
        romBytes[6] = 0; // Mapper 0, horizontal mirroring

        // In PRG ROM: Set reset vector at $FFFC-$FFFD to point to $8000
        int prgStart = 16;
        int resetVectorOffset = prgStart + 16384 - 4;
        romBytes[resetVectorOffset] = 0x00;
        romBytes[resetVectorOffset + 1] = (byte) 0x80;

        // At $8000 (prgStart): Put NOP (0xEA), JMP $8000 (0x4C, 0x00, 0x80)
        romBytes[prgStart] = (byte) 0xEA;
        romBytes[prgStart + 1] = (byte) 0x4C;
        romBytes[prgStart + 2] = (byte) 0x00;
        romBytes[prgStart + 3] = (byte) 0x80;

        NesCartridge cart = NesCartridge.load(new ByteArrayInputStream(romBytes));
        assertEquals(0, cart.mapper);
        assertEquals(16384, cart.prgRom.length);
        assertEquals(8192, cart.chrRom.length);

        NesPpu ppu = new NesPpu(cart);
        NesCpu cpu = new NesCpu(ppu, cart);
        assertEquals(0x8000, cpu.pc);

        // Step CPU and PPU for 1 frame
        for (int sl = 0; sl < 262; sl++) {
            ppu.stepScanline();
            int cyclesTarget = 114;
            int cyc = 0;
            while (cyc < cyclesTarget) {
                cyc += cpu.step();
            }
        }

        assertTrue(ppu.frameComplete);
        assertEquals(256 * 240, ppu.screen.length);
    }

    @Test
    public void snesEmulationInitializesAndStepsFrame() throws Exception {
        // Construct a minimal valid SNES LoROM: 32KB ROM with header at 0x7FC0
        byte[] romBytes = new byte[32768];
        int headerBase = 0x7FC0;
        // Game title: "TEST SNES"
        byte[] title = "TEST SNES".getBytes("ASCII");
        System.arraycopy(title, 0, romBytes, headerBase, title.length);

        // Reset vector at 0x7FFC points to $8000
        romBytes[headerBase + 0x3C] = 0x00;
        romBytes[headerBase + 0x3D] = (byte) 0x80;

        // At $8000: NOP (0xEA), BRA 0 (0x80, 0xFE)
        romBytes[0] = (byte) 0xEA;
        romBytes[1] = (byte) 0x80;
        romBytes[2] = (byte) 0xFE;

        SnesCartridge cart = SnesCartridge.load(new ByteArrayInputStream(romBytes));
        assertTrue(cart.title.startsWith("TEST SNES"));

        SnesPpu ppu = new SnesPpu();
        SnesCpu cpu = new SnesCpu(ppu, cart);
        assertEquals(0x8000, cpu.pc);

        // Step CPU and PPU for 1 frame
        for (int sl = 0; sl < 262; sl++) {
            ppu.stepScanline();
            int cyclesTarget = 350;
            int cyc = 0;
            while (cyc < cyclesTarget) {
                cyc += cpu.step();
            }
        }

        assertTrue(ppu.frameComplete);
        assertEquals(256 * 224, ppu.screen.length);
    }

    @Test
    public void unromContraArchitectureInitializesAndWritesChrRam() throws Exception {
        // Construct an UNROM ROM (Mapper 2): 16 bytes header + 128KB PRG ROM (8 banks) + 0 CHR ROM (uses CHR RAM)
        int prgSize = 8 * 16384;
        byte[] romBytes = new byte[16 + prgSize];
        romBytes[0] = 'N';
        romBytes[1] = 'E';
        romBytes[2] = 'S';
        romBytes[3] = 0x1A;
        romBytes[4] = 8; // 8 x 16KB PRG = 128KB
        romBytes[5] = 0; // 0 CHR banks -> CHR RAM
        romBytes[6] = 0x21; // Mapper 2 (lower nibble 2), vertical mirroring (bit 0 = 1)
        romBytes[7] = 0x00; // Mapper 2 (upper nibble 0)

        // Set reset vector in the LAST fixed bank (Bank 7, $C000-$FFFF)
        int lastBankOffset = 16 + (7 * 16384);
        int resetVectorOffset = lastBankOffset + 16384 - 4;
        romBytes[resetVectorOffset] = 0x00;
        romBytes[resetVectorOffset + 1] = (byte) 0xC0; // points to $C000

        // At $C000: NOP (0xEA), JMP $C000 (0x4C, 0x00, 0xC0)
        romBytes[lastBankOffset] = (byte) 0xEA;
        romBytes[lastBankOffset + 1] = (byte) 0x4C;
        romBytes[lastBankOffset + 2] = (byte) 0x00;
        romBytes[lastBankOffset + 3] = (byte) 0xC0;

        NesCartridge cart = NesCartridge.load(new ByteArrayInputStream(romBytes));
        assertEquals(2, cart.mapper);
        assertTrue(cart.hasChrRam);
        assertTrue(cart.mirrorVertical);
        assertEquals(8192, cart.chrRom.length);

        // Test writing to CHR-RAM via cart.writeChr
        cart.writeChr(0x0010, 0xAA);
        assertEquals(0xAA, cart.readChr(0x0010));

        // Test PRG bank switching for Mapper 2
        // Write bank 3 to $8000
        cart.prgRom[3 * 16384] = (byte) 0x55; // marker byte in bank 3
        cart.writePrg(0x8000, 3);
        assertEquals(0x55, cart.readPrg(0x8000));

        NesPpu ppu = new NesPpu(cart);
        NesCpu cpu = new NesCpu(ppu, cart);
        assertEquals(0xC000, cpu.pc);

        // Step 1 frame
        for (int sl = 0; sl < 262; sl++) {
            ppu.stepScanline();
            int cyclesTarget = 114;
            int cyc = 0;
            while (cyc < cyclesTarget) {
                cyc += cpu.step();
            }
        }
        assertTrue(ppu.frameComplete);
    }
}
