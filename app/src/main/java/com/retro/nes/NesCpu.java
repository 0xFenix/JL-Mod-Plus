package com.retro.nes;

public class NesCpu {
    public final byte[] ram = new byte[2048];
    public int a = 0;
    public int x = 0;
    public int y = 0;
    public int sp = 0xFD;
    public int pc = 0;
    public int p = 0x24; // Status: NV-BDIZC

    public NesPpu ppu;
    public NesCartridge cart;

    // Joypad 1 & 2
    public int joy1State = 0; // Bitmask: A, B, Select, Start, Up, Down, Left, Right
    private int joy1Shift = 0;
    private boolean joyStrobe = false;

    // Cycles executed
    public long cycles = 0;

    public NesCpu(NesPpu ppu, NesCartridge cart) {
        this.ppu = ppu;
        this.cart = cart;
        reset();
    }

    public void reset() {
        a = 0;
        x = 0;
        y = 0;
        sp = 0xFD;
        p = 0x24;
        pc = read16(0xFFFC);
        cycles = 7;
    }

    public int read(int addr) {
        addr &= 0xFFFF;
        if (addr < 0x2000) {
            return ram[addr & 0x07FF] & 0xFF;
        } else if (addr < 0x4000) {
            return ppu.readRegister(addr);
        } else if (addr == 0x4016) {
            if (joyStrobe) {
                return (joy1State & 1) | 0x40;
            }
            int val = (joy1Shift & 1) | 0x40;
            joy1Shift = (joy1Shift >> 1) | 0x80;
            return val;
        } else if (addr >= 0x4020) {
            return cart.readPrg(addr);
        }
        return 0;
    }

    public void write(int addr, int val) {
        addr &= 0xFFFF;
        val &= 0xFF;
        if (addr < 0x2000) {
            ram[addr & 0x07FF] = (byte) val;
        } else if (addr < 0x4000) {
            ppu.writeRegister(addr, val);
        } else if (addr == 0x4014) { // OAM DMA
            int base = val << 8;
            for (int i = 0; i < 256; i++) {
                ppu.oam[(ppu.oamAddr + i) & 0xFF] = (byte) read(base + i);
            }
            cycles += 513;
        } else if (addr == 0x4016) {
            if (joyStrobe && (val & 1) == 0) {
                joy1Shift = joy1State;
            }
            joyStrobe = (val & 1) != 0;
        } else if (addr >= 0x4020) {
            cart.writePrg(addr, val);
        }
    }

    public int read16(int addr) {
        return read(addr) | (read(addr + 1) << 8);
    }

    public int read16Wrap(int addr) {
        int lo = read(addr);
        int hi = read((addr & 0xFF00) | ((addr + 1) & 0xFF));
        return lo | (hi << 8);
    }

    private void push(int val) {
        write(0x0100 | sp, val);
        sp = (sp - 1) & 0xFF;
    }

    private int pop() {
        sp = (sp + 1) & 0xFF;
        return read(0x0100 | sp);
    }

    public void triggerNmi() {
        push((pc >> 8) & 0xFF);
        push(pc & 0xFF);
        push((p & ~0x10) | 0x20); // Push P with B flag cleared
        p |= 0x04; // Set Interrupt Disable
        pc = read16(0xFFFA);
        cycles += 7;
    }

    public void triggerIrq() {
        if ((p & 0x04) == 0) {
            push((pc >> 8) & 0xFF);
            push(pc & 0xFF);
            push((p & ~0x10) | 0x20);
            p |= 0x04;
            pc = read16(0xFFFE);
            cycles += 7;
        }
    }

    private void setZ(int v) {
        if ((v & 0xFF) == 0) p |= 0x02; else p &= ~0x02;
    }

    private void setN(int v) {
        if ((v & 0x80) != 0) p |= 0x80; else p &= ~0x80;
    }

    private void setZN(int v) {
        setZ(v);
        setN(v);
    }

    // Step a single 6502 instruction
    public int step() {
        if (ppu.nmiTriggered) {
            ppu.nmiTriggered = false;
            triggerNmi();
            return 7;
        }
        if (cart.irqPending) {
            cart.irqPending = false;
            triggerIrq();
            return 7;
        }

        int op = read(pc++);
        int cyc = 2;

        switch (op) {
            // NOP
            case 0xEA -> cyc = 2;

            // LDA
            case 0xA9 -> { a = read(pc++); setZN(a); cyc = 2; }
            case 0xA5 -> { a = read(read(pc++)); setZN(a); cyc = 3; }
            case 0xB5 -> { a = read((read(pc++) + x) & 0xFF); setZN(a); cyc = 4; }
            case 0xAD -> { a = read(read16(pc)); pc += 2; setZN(a); cyc = 4; }
            case 0xBD -> { a = read(read16(pc) + x); pc += 2; setZN(a); cyc = 4; }
            case 0xB9 -> { a = read(read16(pc) + y); pc += 2; setZN(a); cyc = 4; }
            case 0xA1 -> { int ptr = (read(pc++) + x) & 0xFF; a = read(read16Wrap(ptr)); setZN(a); cyc = 6; }
            case 0xB1 -> { int ptr = read(pc++); a = read(read16Wrap(ptr) + y); setZN(a); cyc = 5; }

            // LDX
            case 0xA2 -> { x = read(pc++); setZN(x); cyc = 2; }
            case 0xA6 -> { x = read(read(pc++)); setZN(x); cyc = 3; }
            case 0xB6 -> { x = read((read(pc++) + y) & 0xFF); setZN(x); cyc = 4; }
            case 0xAE -> { x = read(read16(pc)); pc += 2; setZN(x); cyc = 4; }
            case 0xBE -> { x = read(read16(pc) + y); pc += 2; setZN(x); cyc = 4; }

            // LDY
            case 0xA0 -> { y = read(pc++); setZN(y); cyc = 2; }
            case 0xA4 -> { y = read(read(pc++)); setZN(y); cyc = 3; }
            case 0xB4 -> { y = read((read(pc++) + x) & 0xFF); setZN(y); cyc = 4; }
            case 0xAC -> { y = read(read16(pc)); pc += 2; setZN(y); cyc = 4; }
            case 0xBC -> { y = read(read16(pc) + x); pc += 2; setZN(y); cyc = 4; }

            // STA
            case 0x85 -> { write(read(pc++), a); cyc = 3; }
            case 0x95 -> { write((read(pc++) + x) & 0xFF, a); cyc = 4; }
            case 0x8D -> { write(read16(pc), a); pc += 2; cyc = 4; }
            case 0x9D -> { write(read16(pc) + x, a); pc += 2; cyc = 5; }
            case 0x99 -> { write(read16(pc) + y, a); pc += 2; cyc = 5; }
            case 0x81 -> { int ptr = (read(pc++) + x) & 0xFF; write(read16Wrap(ptr), a); cyc = 6; }
            case 0x91 -> { int ptr = read(pc++); write(read16Wrap(ptr) + y, a); cyc = 6; }

            // STX
            case 0x86 -> { write(read(pc++), x); cyc = 3; }
            case 0x96 -> { write((read(pc++) + y) & 0xFF, x); cyc = 4; }
            case 0x8E -> { write(read16(pc), x); pc += 2; cyc = 4; }

            // STY
            case 0x84 -> { write(read(pc++), y); cyc = 3; }
            case 0x94 -> { write((read(pc++) + x) & 0xFF, y); cyc = 4; }
            case 0x8C -> { write(read16(pc), y); pc += 2; cyc = 4; }

            // JMP
            case 0x4C -> { pc = read16(pc); cyc = 3; }
            case 0x6C -> { int addr = read16(pc); pc = read16Wrap(addr); cyc = 5; }

            // JSR / RTS
            case 0x20 -> { push(((pc + 1) >> 8) & 0xFF); push((pc + 1) & 0xFF); pc = read16(pc); cyc = 6; }
            case 0x60 -> { pc = (pop() | (pop() << 8)) + 1; cyc = 6; }

            // RTI
            case 0x40 -> { p = (pop() & ~0x10) | 0x20; pc = pop() | (pop() << 8); cyc = 6; }

            // Branching
            case 0x10 -> { cyc = branch((p & 0x80) == 0); } // BPL
            case 0x30 -> { cyc = branch((p & 0x80) != 0); } // BMI
            case 0x50 -> { cyc = branch((p & 0x40) == 0); } // BVC
            case 0x70 -> { cyc = branch((p & 0x40) != 0); } // BVS
            case 0x90 -> { cyc = branch((p & 0x01) == 0); } // BCC
            case 0xB0 -> { cyc = branch((p & 0x01) != 0); } // BCS
            case 0xD0 -> { cyc = branch((p & 0x02) == 0); } // BNE
            case 0xF0 -> { cyc = branch((p & 0x02) != 0); } // BEQ

            // Status flags
            case 0x18 -> { p &= ~0x01; cyc = 2; } // CLC
            case 0x38 -> { p |= 0x01; cyc = 2; }  // SEC
            case 0x58 -> { p &= ~0x04; cyc = 2; } // CLI
            case 0x78 -> { p |= 0x04; cyc = 2; }  // SEI
            case 0xB8 -> { p &= ~0x40; cyc = 2; } // CLV
            case 0xD8 -> { p &= ~0x08; cyc = 2; } // CLD
            case 0xF8 -> { p |= 0x08; cyc = 2; }  // SED

            // Transfers
            case 0xAA -> { x = a; setZN(x); cyc = 2; } // TAX
            case 0x8A -> { a = x; setZN(a); cyc = 2; } // TXA
            case 0xA8 -> { y = a; setZN(y); cyc = 2; } // TAY
            case 0x98 -> { a = y; setZN(a); cyc = 2; } // TYA
            case 0xBA -> { x = sp; setZN(x); cyc = 2; } // TSX
            case 0x9A -> { sp = x; cyc = 2; } // TXS

            // Stack
            case 0x48 -> { push(a); cyc = 3; } // PHA
            case 0x68 -> { a = pop(); setZN(a); cyc = 4; } // PLA
            case 0x08 -> { push(p | 0x30); cyc = 3; } // PHP
            case 0x28 -> { p = (pop() & ~0x10) | 0x20; cyc = 4; } // PLP

            // INX / DEX / INY / DEY
            case 0xE8 -> { x = (x + 1) & 0xFF; setZN(x); cyc = 2; }
            case 0xCA -> { x = (x - 1) & 0xFF; setZN(x); cyc = 2; }
            case 0xC8 -> { y = (y + 1) & 0xFF; setZN(y); cyc = 2; }
            case 0x88 -> { y = (y - 1) & 0xFF; setZN(y); cyc = 2; }

            // Arithmetic: ADC
            case 0x69 -> { adc(read(pc++)); cyc = 2; }
            case 0x65 -> { adc(read(read(pc++))); cyc = 3; }
            case 0x75 -> { adc(read((read(pc++) + x) & 0xFF)); cyc = 4; }
            case 0x6D -> { adc(read(read16(pc))); pc += 2; cyc = 4; }
            case 0x7D -> { adc(read(read16(pc) + x)); pc += 2; cyc = 4; }
            case 0x79 -> { adc(read(read16(pc) + y)); pc += 2; cyc = 4; }
            case 0x61 -> { int ptr = (read(pc++) + x) & 0xFF; adc(read(read16Wrap(ptr))); cyc = 6; }
            case 0x71 -> { int ptr = read(pc++); adc(read(read16Wrap(ptr) + y)); cyc = 5; }

            // Arithmetic: SBC
            case 0xE9 -> { sbc(read(pc++)); cyc = 2; }
            case 0xE5 -> { sbc(read(read(pc++))); cyc = 3; }
            case 0xF5 -> { sbc(read((read(pc++) + x) & 0xFF)); cyc = 4; }
            case 0xED -> { sbc(read(read16(pc))); pc += 2; cyc = 4; }
            case 0xFD -> { sbc(read(read16(pc) + x)); pc += 2; cyc = 4; }
            case 0xF9 -> { sbc(read(read16(pc) + y)); pc += 2; cyc = 4; }
            case 0xE1 -> { int ptr = (read(pc++) + x) & 0xFF; sbc(read(read16Wrap(ptr))); cyc = 6; }
            case 0xF1 -> { int ptr = read(pc++); sbc(read(read16Wrap(ptr) + y)); cyc = 5; }

            // Comparisons: CMP
            case 0xC9 -> { cmp(a, read(pc++)); cyc = 2; }
            case 0xC5 -> { cmp(a, read(read(pc++))); cyc = 3; }
            case 0xD5 -> { cmp(a, read((read(pc++) + x) & 0xFF)); cyc = 4; }
            case 0xCD -> { cmp(a, read(read16(pc))); pc += 2; cyc = 4; }
            case 0xDD -> { cmp(a, read(read16(pc) + x)); pc += 2; cyc = 4; }
            case 0xD9 -> { cmp(a, read(read16(pc) + y)); pc += 2; cyc = 4; }
            case 0xC1 -> { int ptr = (read(pc++) + x) & 0xFF; cmp(a, read(read16Wrap(ptr))); cyc = 6; }
            case 0xD1 -> { int ptr = read(pc++); cmp(a, read(read16Wrap(ptr) + y)); cyc = 5; }

            // CPX / CPY
            case 0xE0 -> { cmp(x, read(pc++)); cyc = 2; }
            case 0xE4 -> { cmp(x, read(read(pc++))); cyc = 3; }
            case 0xEC -> { cmp(x, read(read16(pc))); pc += 2; cyc = 4; }
            case 0xC0 -> { cmp(y, read(pc++)); cyc = 2; }
            case 0xC4 -> { cmp(y, read(read(pc++))); cyc = 3; }
            case 0xCC -> { cmp(y, read(read16(pc))); pc += 2; cyc = 4; }

            // Bitwise: AND
            case 0x29 -> { a &= read(pc++); setZN(a); cyc = 2; }
            case 0x25 -> { a &= read(read(pc++)); setZN(a); cyc = 3; }
            case 0x35 -> { a &= read((read(pc++) + x) & 0xFF); setZN(a); cyc = 4; }
            case 0x2D -> { a &= read(read16(pc)); pc += 2; setZN(a); cyc = 4; }
            case 0x3D -> { a &= read(read16(pc) + x); pc += 2; setZN(a); cyc = 4; }
            case 0x39 -> { a &= read(read16(pc) + y); pc += 2; setZN(a); cyc = 4; }
            case 0x21 -> { int ptr = (read(pc++) + x) & 0xFF; a &= read(read16Wrap(ptr)); setZN(a); cyc = 6; }
            case 0x31 -> { int ptr = read(pc++); a &= read(read16Wrap(ptr) + y); setZN(a); cyc = 5; }

            // Bitwise: ORA
            case 0x09 -> { a |= read(pc++); setZN(a); cyc = 2; }
            case 0x05 -> { a |= read(read(pc++)); setZN(a); cyc = 3; }
            case 0x15 -> { a |= read((read(pc++) + x) & 0xFF); setZN(a); cyc = 4; }
            case 0x0D -> { a |= read(read16(pc)); pc += 2; setZN(a); cyc = 4; }
            case 0x1D -> { a |= read(read16(pc) + x); pc += 2; setZN(a); cyc = 4; }
            case 0x19 -> { a |= read(read16(pc) + y); pc += 2; setZN(a); cyc = 4; }
            case 0x01 -> { int ptr = (read(pc++) + x) & 0xFF; a |= read(read16Wrap(ptr)); setZN(a); cyc = 6; }
            case 0x11 -> { int ptr = read(pc++); a |= read(read16Wrap(ptr) + y); setZN(a); cyc = 5; }

            // Bitwise: EOR
            case 0x49 -> { a ^= read(pc++); setZN(a); cyc = 2; }
            case 0x45 -> { a ^= read(read(pc++)); setZN(a); cyc = 3; }
            case 0x55 -> { a ^= read((read(pc++) + x) & 0xFF); setZN(a); cyc = 4; }
            case 0x4D -> { a ^= read(read16(pc)); pc += 2; setZN(a); cyc = 4; }
            case 0x5D -> { a ^= read(read16(pc) + x); pc += 2; setZN(a); cyc = 4; }
            case 0x59 -> { a ^= read(read16(pc) + y); pc += 2; setZN(a); cyc = 4; }
            case 0x41 -> { int ptr = (read(pc++) + x) & 0xFF; a ^= read(read16Wrap(ptr)); setZN(a); cyc = 6; }
            case 0x51 -> { int ptr = read(pc++); a ^= read(read16Wrap(ptr) + y); setZN(a); cyc = 5; }

            // BIT
            case 0x24 -> { int v = read(read(pc++)); setZ(a & v); p = (p & ~0xC0) | (v & 0xC0); cyc = 3; }
            case 0x2C -> { int v = read(read16(pc)); pc += 2; setZ(a & v); p = (p & ~0xC0) | (v & 0xC0); cyc = 4; }

            // Increments / Decrements
            case 0xE6 -> { int addr = read(pc++); int v = (read(addr) + 1) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0xF6 -> { int addr = (read(pc++) + x) & 0xFF; int v = (read(addr) + 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0xEE -> { int addr = read16(pc); pc += 2; int v = (read(addr) + 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0xFE -> { int addr = read16(pc) + x; pc += 2; int v = (read(addr) + 1) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            case 0xC6 -> { int addr = read(pc++); int v = (read(addr) - 1) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0xD6 -> { int addr = (read(pc++) + x) & 0xFF; int v = (read(addr) - 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0xCE -> { int addr = read16(pc); pc += 2; int v = (read(addr) - 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0xDE -> { int addr = read16(pc) + x; pc += 2; int v = (read(addr) - 1) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            // Shifts: ASL
            case 0x0A -> { p = (p & ~1) | ((a >> 7) & 1); a = (a << 1) & 0xFF; setZN(a); cyc = 2; }
            case 0x06 -> { int addr = read(pc++); int v = read(addr); p = (p & ~1) | ((v >> 7) & 1); v = (v << 1) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0x16 -> { int addr = (read(pc++) + x) & 0xFF; int v = read(addr); p = (p & ~1) | ((v >> 7) & 1); v = (v << 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x0E -> { int addr = read16(pc); pc += 2; int v = read(addr); p = (p & ~1) | ((v >> 7) & 1); v = (v << 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x1E -> { int addr = read16(pc) + x; pc += 2; int v = read(addr); p = (p & ~1) | ((v >> 7) & 1); v = (v << 1) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            // Shifts: LSR
            case 0x4A -> { p = (p & ~1) | (a & 1); a = (a >> 1) & 0xFF; setZN(a); cyc = 2; }
            case 0x46 -> { int addr = read(pc++); int v = read(addr); p = (p & ~1) | (v & 1); v = (v >> 1) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0x56 -> { int addr = (read(pc++) + x) & 0xFF; int v = read(addr); p = (p & ~1) | (v & 1); v = (v >> 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x4E -> { int addr = read16(pc); pc += 2; int v = read(addr); p = (p & ~1) | (v & 1); v = (v >> 1) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x5E -> { int addr = read16(pc) + x; pc += 2; int v = read(addr); p = (p & ~1) | (v & 1); v = (v >> 1) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            // Rotates: ROL
            case 0x2A -> { int c = p & 1; p = (p & ~1) | ((a >> 7) & 1); a = ((a << 1) | c) & 0xFF; setZN(a); cyc = 2; }
            case 0x26 -> { int addr = read(pc++); int v = read(addr); int c = p & 1; p = (p & ~1) | ((v >> 7) & 1); v = ((v << 1) | c) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0x36 -> { int addr = (read(pc++) + x) & 0xFF; int v = read(addr); int c = p & 1; p = (p & ~1) | ((v >> 7) & 1); v = ((v << 1) | c) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x2E -> { int addr = read16(pc); pc += 2; int v = read(addr); int c = p & 1; p = (p & ~1) | ((v >> 7) & 1); v = ((v << 1) | c) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x3E -> { int addr = read16(pc) + x; pc += 2; int v = read(addr); int c = p & 1; p = (p & ~1) | ((v >> 7) & 1); v = ((v << 1) | c) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            // Rotates: ROR
            case 0x6A -> { int c = p & 1; p = (p & ~1) | (a & 1); a = ((a >> 1) | (c << 7)) & 0xFF; setZN(a); cyc = 2; }
            case 0x66 -> { int addr = read(pc++); int v = read(addr); int c = p & 1; p = (p & ~1) | (v & 1); v = ((v >> 1) | (c << 7)) & 0xFF; write(addr, v); setZN(v); cyc = 5; }
            case 0x76 -> { int addr = (read(pc++) + x) & 0xFF; int v = read(addr); int c = p & 1; p = (p & ~1) | (v & 1); v = ((v >> 1) | (c << 7)) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x6E -> { int addr = read16(pc); pc += 2; int v = read(addr); int c = p & 1; p = (p & ~1) | (v & 1); v = ((v >> 1) | (c << 7)) & 0xFF; write(addr, v); setZN(v); cyc = 6; }
            case 0x7E -> { int addr = read16(pc) + x; pc += 2; int v = read(addr); int c = p & 1; p = (p & ~1) | (v & 1); v = ((v >> 1) | (c << 7)) & 0xFF; write(addr, v); setZN(v); cyc = 7; }

            default -> cyc = 2; // Unofficial opcodes treated as NOP
        }

        cycles += cyc;
        return cyc;
    }

    private int branch(boolean cond) {
        int offset = (byte) read(pc++);
        if (cond) {
            pc = (pc + offset) & 0xFFFF;
            return 3;
        }
        return 2;
    }

    private void adc(int val) {
        int sum = a + val + (p & 1);
        if (~(a ^ val) != 0 && ((a ^ sum) & 0x80) != 0) p |= 0x40; else p &= ~0x40; // Overflow
        if (sum > 0xFF) p |= 0x01; else p &= ~0x01; // Carry
        a = sum & 0xFF;
        setZN(a);
    }

    private void sbc(int val) {
        adc(~val & 0xFF);
    }

    private void cmp(int reg, int val) {
        int res = reg - val;
        if (reg >= val) p |= 0x01; else p &= ~0x01;
        setZN(res & 0xFF);
    }
}
