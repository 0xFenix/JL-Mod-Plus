package com.retro.snes;

public class SnesCpu {
    public final byte[] wram = new byte[131072]; // 128KB WRAM ($7E-$7F)
    public int a = 0;       // Accumulator (16-bit or 8-bit)
    public int x = 0;       // X register (16-bit or 8-bit)
    public int y = 0;       // Y register (16-bit or 8-bit)
    public int sp = 0x01FF; // Stack pointer
    public int dp = 0;      // Direct page
    public int pc = 0;      // Program counter
    public int pbr = 0;     // Program bank register
    public int dbr = 0;     // Data bank register
    public int p = 0x34;    // Status register: N V M X D I Z C
    public boolean e = true;// Emulation mode flag (starts true on reset)

    public SnesPpu ppu;
    public SnesCartridge cart;

    // Joypad 1 state (16-bit: B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R)
    public int joy1 = 0;

    // Interrupts & control
    public boolean nmiEnabled = false;
    public long cycles = 0;

    public SnesCpu(SnesPpu ppu, SnesCartridge cart) {
        this.ppu = ppu;
        this.cart = cart;
        reset();
    }

    public void reset() {
        e = true;
        p = 0x34; // M=1, X=1 (8-bit registers in emulation mode)
        pbr = 0;
        dbr = 0;
        dp = 0;
        sp = 0x01FF;
        a = 0;
        x = 0;
        y = 0;
        pc = read16(0x00, 0xFFFC); // Emulation mode reset vector
        cycles = 0;
    }

    public int read(int bank, int addr) {
        bank &= 0xFF;
        addr &= 0xFFFF;

        if (bank == 0x7E || bank == 0x7F) {
            int offset = ((bank - 0x7E) << 16) | addr;
            return wram[offset % wram.length] & 0xFF;
        }

        if ((bank <= 0x3F) || (bank >= 0x80 && bank <= 0xBF)) {
            if (addr < 0x2000) {
                return wram[addr & 0x1FFF] & 0xFF;
            } else if (addr >= 0x2100 && addr <= 0x213F) {
                return ppu.readRegister(addr);
            } else if (addr == 0x4210) {
                return (ppu.scanline >= 225 ? 0x80 : 0) | 0x02; // RDNMI
            } else if (addr == 0x4218) {
                return joy1 & 0xFF; // JOY1L
            } else if (addr == 0x4219) {
                return (joy1 >> 8) & 0xFF; // JOY1H
            } else if (addr >= 0x8000) {
                return cart.read(bank, addr);
            }
        }

        return cart.read(bank, addr);
    }

    public void write(int bank, int addr, int val) {
        bank &= 0xFF;
        addr &= 0xFFFF;
        val &= 0xFF;

        if (bank == 0x7E || bank == 0x7F) {
            int offset = ((bank - 0x7E) << 16) | addr;
            wram[offset % wram.length] = (byte) val;
            return;
        }

        if ((bank <= 0x3F) || (bank >= 0x80 && bank <= 0xBF)) {
            if (addr < 0x2000) {
                wram[addr & 0x1FFF] = (byte) val;
                return;
            } else if (addr >= 0x2100 && addr <= 0x213F) {
                ppu.writeRegister(addr, val);
                return;
            } else if (addr == 0x4200) { // NMITIMEN
                nmiEnabled = (val & 0x80) != 0;
                return;
            } else if (addr >= 0x8000) {
                cart.write(bank, addr, val);
                return;
            }
        }

        cart.write(bank, addr, val);
    }

    public int read16(int bank, int addr) {
        return read(bank, addr) | (read(bank, addr + 1) << 8);
    }

    public void write16(int bank, int addr, int val) {
        write(bank, addr, val & 0xFF);
        write(bank, addr + 1, (val >> 8) & 0xFF);
    }

    private void push8(int val) {
        write(0, sp, val);
        sp = e ? (0x0100 | ((sp - 1) & 0xFF)) : ((sp - 1) & 0xFFFF);
    }

    private void push16(int val) {
        push8((val >> 8) & 0xFF);
        push8(val & 0xFF);
    }

    private int pop8() {
        sp = e ? (0x0100 | ((sp + 1) & 0xFF)) : ((sp + 1) & 0xFFFF);
        return read(0, sp);
    }

    private int pop16() {
        int lo = pop8();
        int hi = pop8();
        return lo | (hi << 8);
    }

    public void triggerNmi() {
        if (!nmiEnabled) return;
        if (!e) push8(pbr);
        push16(pc);
        push8(p);
        p |= 0x04; // Set Interrupt Disable
        pbr = 0;
        pc = read16(0, e ? 0xFFFA : 0xFFEA);
        cycles += 8;
    }

    private void setZN8(int val) {
        val &= 0xFF;
        if (val == 0) p |= 0x02; else p &= ~0x02;
        if ((val & 0x80) != 0) p |= 0x80; else p &= ~0x80;
    }

    private void setZN16(int val) {
        val &= 0xFFFF;
        if (val == 0) p |= 0x02; else p &= ~0x02;
        if ((val & 0x8000) != 0) p |= 0x80; else p &= ~0x80;
    }

    // Step 1 instruction
    public int step() {
        if (ppu.nmiTriggered && nmiEnabled) {
            ppu.nmiTriggered = false;
            triggerNmi();
            return 8;
        }

        int op = read(pbr, pc++);
        int cyc = 3;

        boolean mFlag = e || (p & 0x20) != 0; // M=1: 8-bit A, M=0: 16-bit A
        boolean xFlag = e || (p & 0x10) != 0; // X=1: 8-bit X/Y, X=0: 16-bit X/Y

        switch (op) {
            // NOP
            case 0xEA -> cyc = 2;

            // CLC / SEC / CLI / SEI
            case 0x18 -> { p &= ~0x01; cyc = 2; }
            case 0x38 -> { p |= 0x01; cyc = 2; }
            case 0x58 -> { p &= ~0x04; cyc = 2; }
            case 0x78 -> { p |= 0x04; cyc = 2; }
            case 0xC2 -> { // REP (Reset Status Bits)
                int imm = read(pbr, pc++);
                p &= ~imm;
                cyc = 3;
            }
            case 0xE2 -> { // SEP (Set Status Bits)
                int imm = read(pbr, pc++);
                p |= imm;
                cyc = 3;
            }
            case 0xFB -> { // XCE (Exchange Carry with Emulation)
                boolean oldC = (p & 1) != 0;
                boolean oldE = e;
                e = oldC;
                if (oldE) p |= 1; else p &= ~1;
                if (e) p |= 0x30; // 8-bit mode enforced in emulation
                cyc = 2;
            }

            // LDA Immediate
            case 0xA9 -> {
                if (mFlag) {
                    a = (a & 0xFF00) | read(pbr, pc++);
                    setZN8(a);
                    cyc = 2;
                } else {
                    a = read16(pbr, pc);
                    pc += 2;
                    setZN16(a);
                    cyc = 3;
                }
            }

            // LDA Absolute
            case 0xAD -> {
                int addr = read16(pbr, pc);
                pc += 2;
                if (mFlag) {
                    a = (a & 0xFF00) | read(dbr, addr);
                    setZN8(a);
                    cyc = 4;
                } else {
                    a = read16(dbr, addr);
                    setZN16(a);
                    cyc = 5;
                }
            }

            // STA Absolute
            case 0x8D -> {
                int addr = read16(pbr, pc);
                pc += 2;
                if (mFlag) {
                    write(dbr, addr, a & 0xFF);
                    cyc = 4;
                } else {
                    write16(dbr, addr, a);
                    cyc = 5;
                }
            }

            // STA Long
            case 0x8F -> {
                int addr = read16(pbr, pc);
                pc += 2;
                int bank = read(pbr, pc++);
                if (mFlag) {
                    write(bank, addr, a & 0xFF);
                    cyc = 5;
                } else {
                    write16(bank, addr, a);
                    cyc = 6;
                }
            }

            // LDX Immediate
            case 0xA2 -> {
                if (xFlag) {
                    x = read(pbr, pc++);
                    setZN8(x);
                    cyc = 2;
                } else {
                    x = read16(pbr, pc);
                    pc += 2;
                    setZN16(x);
                    cyc = 3;
                }
            }

            // LDY Immediate
            case 0xA0 -> {
                if (xFlag) {
                    y = read(pbr, pc++);
                    setZN8(y);
                    cyc = 2;
                } else {
                    y = read16(pbr, pc);
                    pc += 2;
                    setZN16(y);
                    cyc = 3;
                }
            }

            // JMP Absolute
            case 0x4C -> { pc = read16(pbr, pc); cyc = 3; }
            // JMP Long
            case 0x5C -> {
                int addr = read16(pbr, pc);
                pc += 2;
                pbr = read(pbr, pc++);
                pc = addr;
                cyc = 4;
            }

            // JSR Absolute
            case 0x20 -> {
                push16(pc + 1);
                pc = read16(pbr, pc);
                cyc = 6;
            }
            // JSL (Long subroutine call)
            case 0x22 -> {
                push8(pbr);
                push16(pc + 2);
                int addr = read16(pbr, pc);
                pbr = read(pbr, pc + 2);
                pc = addr;
                cyc = 8;
            }
            // RTS
            case 0x60 -> { pc = pop16() + 1; cyc = 6; }
            // RTL
            case 0x6B -> { pc = pop16() + 1; pbr = pop8(); cyc = 6; }

            // Branching
            case 0x10 -> cyc = branch((p & 0x80) == 0); // BPL
            case 0x30 -> cyc = branch((p & 0x80) != 0); // BMI
            case 0x90 -> cyc = branch((p & 0x01) == 0); // BCC
            case 0xB0 -> cyc = branch((p & 0x01) != 0); // BCS
            case 0xD0 -> cyc = branch((p & 0x02) == 0); // BNE
            case 0xF0 -> cyc = branch((p & 0x02) != 0); // BEQ
            case 0x80 -> cyc = branch(true);            // BRA

            // Transfers
            case 0xAA -> { x = a; if (xFlag) setZN8(x); else setZN16(x); cyc = 2; } // TAX
            case 0x8A -> { a = (a & 0xFF00) | (x & 0xFF); setZN8(a); cyc = 2; }     // TXA
            case 0xA8 -> { y = a; if (xFlag) setZN8(y); else setZN16(y); cyc = 2; } // TAY
            case 0x98 -> { a = (a & 0xFF00) | (y & 0xFF); setZN8(a); cyc = 2; }     // TYA
            case 0xBA -> { x = sp; if (xFlag) setZN8(x); else setZN16(x); cyc = 2; }// TSX
            case 0x9A -> { sp = x; cyc = 2; }                                       // TXS

            // INX / DEX / INY / DEY
            case 0xE8 -> { x = (x + 1) & (xFlag ? 0xFF : 0xFFFF); if (xFlag) setZN8(x); else setZN16(x); cyc = 2; }
            case 0xCA -> { x = (x - 1) & (xFlag ? 0xFF : 0xFFFF); if (xFlag) setZN8(x); else setZN16(x); cyc = 2; }
            case 0xC8 -> { y = (y + 1) & (xFlag ? 0xFF : 0xFFFF); if (xFlag) setZN8(y); else setZN16(y); cyc = 2; }
            case 0x88 -> { y = (y - 1) & (xFlag ? 0xFF : 0xFFFF); if (xFlag) setZN8(y); else setZN16(y); cyc = 2; }

            // PHA / PLA
            case 0x48 -> { if (mFlag) push8(a); else push16(a); cyc = 3; }
            case 0x68 -> { if (mFlag) { a = (a & 0xFF00) | pop8(); setZN8(a); } else { a = pop16(); setZN16(a); } cyc = 4; }

            default -> cyc = 2;
        }

        cycles += cyc;
        return cyc;
    }

    private int branch(boolean cond) {
        int offset = (byte) read(pbr, pc++);
        if (cond) {
            pc = (pc + offset) & 0xFFFF;
            return 3;
        }
        return 2;
    }
}
