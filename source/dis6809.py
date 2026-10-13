"""Minimal 6809 disassembler sufficient for reading Mirage OS code."""

# inherent opcodes
INH = {
    0x12:"NOP",0x13:"SYNC",0x19:"DAA",0x1D:"SEX",0x39:"RTS",0x3A:"ABX",
    0x3B:"RTI",0x3D:"MUL",0x3F:"SWI",0x40:"NEGA",0x43:"COMA",0x44:"LSRA",
    0x46:"RORA",0x47:"ASRA",0x48:"ASLA",0x49:"ROLA",0x4A:"DECA",0x4C:"INCA",
    0x4D:"TSTA",0x4F:"CLRA",0x50:"NEGB",0x53:"COMB",0x54:"LSRB",0x56:"RORB",
    0x57:"ASRB",0x58:"ASLB",0x59:"ROLB",0x5A:"DECB",0x5C:"INCB",0x5D:"TSTB",
    0x5F:"CLRB",
}
REGS = {0:"D",1:"X",2:"Y",3:"U",4:"S",5:"PC",8:"A",9:"B",10:"CC",11:"DP"}
# branches
BR = {0x20:"BRA",0x21:"BRN",0x22:"BHI",0x23:"BLS",0x24:"BCC",0x25:"BCS",
      0x26:"BNE",0x27:"BEQ",0x28:"BVC",0x29:"BVS",0x2A:"BPL",0x2B:"BMI",
      0x2C:"BGE",0x2D:"BLT",0x2E:"BGT",0x2F:"BLE",0x8D:"BSR"}
# indexed register field
IDXREG = {0:"X",1:"Y",2:"U",3:"S"}

# opcode -> (mnemonic, addressing): addressing in imm8/imm16/dir/idx/ext/rel8/rel16/inh
# Build the main table from operation groups.
def _build():
    t = {}
    # accumulator/memory ops: base patterns
    grp = {
        "SUB":0x80,"CMP":0x81,"SBC":0x82,"AND":0x84,"BIT":0x85,"LD":0x86,
        "EOR":0x88,"ADC":0x89,"OR":0x8A,"ADD":0x8B,
    }
    # A ops 0x80-0x8B(imm), 0x90 dir,0xA0 idx,0xB0 ext ; ST has no imm
    aops = {0x80:"SUBA",0x81:"CMPA",0x82:"SBCA",0x83:"SUBD",0x84:"ANDA",
            0x85:"BITA",0x86:"LDA",0x88:"EORA",0x89:"ADCA",0x8A:"ORA",
            0x8B:"ADDA",0x8C:"CMPX",0x8E:"LDX"}
    for base,is16 in [(0x80,False)]:
        pass
    # We'll just hardcode the common ones we need for reading.
    def add(op,mn,mode): t[op]=(mn,mode)
    # immediate group A
    for op,mn in {0x80:"SUBA",0x81:"CMPA",0x82:"SBCA",0x84:"ANDA",0x85:"BITA",
                  0x86:"LDA",0x88:"EORA",0x89:"ADCA",0x8A:"ORA",0x8B:"ADDA"}.items():
        add(op,mn,"imm8"); add(op+0x10,mn,"dir"); add(op+0x20,mn,"idx"); add(op+0x30,mn,"ext")
    add(0x83,"SUBD","imm16"); add(0x93,"SUBD","dir"); add(0xA3,"SUBD","idx"); add(0xB3,"SUBD","ext")
    add(0x8C,"CMPX","imm16"); add(0x9C,"CMPX","dir"); add(0xAC,"CMPX","idx"); add(0xBC,"CMPX","ext")
    add(0x8E,"LDX","imm16"); add(0x9E,"LDX","dir"); add(0xAE,"LDX","idx"); add(0xBE,"LDX","ext")
    add(0x97,"STA","dir"); add(0xA7,"STA","idx"); add(0xB7,"STA","ext")
    add(0x9F,"STX","dir"); add(0xAF,"STX","idx"); add(0xBF,"STX","ext")
    # B group
    for op,mn in {0xC0:"SUBB",0xC1:"CMPB",0xC2:"SBCB",0xC4:"ANDB",0xC5:"BITB",
                  0xC6:"LDB",0xC8:"EORB",0xC9:"ADCB",0xCA:"ORB",0xCB:"ADDB"}.items():
        add(op,mn,"imm8"); add(op+0x10,mn,"dir"); add(op+0x20,mn,"idx"); add(op+0x30,mn,"ext")
    add(0xCC,"LDD","imm16"); add(0xDC,"LDD","dir"); add(0xEC,"LDD","idx"); add(0xFC,"LDD","ext")
    add(0xC3,"ADDD","imm16"); add(0xD3,"ADDD","dir"); add(0xE3,"ADDD","idx"); add(0xF3,"ADDD","ext")
    add(0xDD,"STD","dir"); add(0xED,"STD","idx"); add(0xFD,"STD","ext")
    add(0xD7,"STB","dir"); add(0xE7,"STB","idx"); add(0xF7,"STB","ext")
    add(0xCE,"LDU","imm16"); add(0xDE,"LDU","dir"); add(0xEE,"LDU","idx"); add(0xFE,"LDU","ext")
    add(0xDF,"STU","dir"); add(0xEF,"STU","idx"); add(0xFF,"STU","ext")
    # jmp/jsr + rmw
    for op,mn in {0x00:"NEG",0x03:"COM",0x04:"LSR",0x06:"ROR",0x07:"ASR",
                  0x08:"ASL",0x09:"ROL",0x0A:"DEC",0x0C:"INC",0x0D:"TST",
                  0x0E:"JMP",0x0F:"CLR"}.items():
        add(op,mn,"dir"); add(op+0x60,mn,"idx"); add(op+0x70,mn,"ext")
    add(0x9D,"JSR","dir"); add(0xAD,"JSR","idx"); add(0xBD,"JSR","ext")
    add(0x30,"LEAX","idx"); add(0x31,"LEAY","idx"); add(0x32,"LEAS","idx"); add(0x33,"LEAU","idx")
    return t

MAIN = _build()


def _idx(mem, p):
    """decode indexed postbyte at mem[p]; return (str, bytes_consumed)."""
    pb = mem[p]; n = 1
    reg = IDXREG[(pb >> 5) & 3]
    if not (pb & 0x80):
        off = pb & 0x1F
        if off & 0x10: off -= 0x20
        return f"{off},{reg}", n
    ind = (pb >> 4) & 1
    mode = pb & 0x0F
    s = ""
    if mode == 0x4: s = f",{reg}"
    elif mode == 0x0: s = f",{reg}+"
    elif mode == 0x1: s = f",{reg}++"
    elif mode == 0x2: s = f",-{reg}"
    elif mode == 0x3: s = f",--{reg}"
    elif mode == 0x6: s = f"A,{reg}"
    elif mode == 0x5: s = f"B,{reg}"
    elif mode == 0xB: s = f"D,{reg}"
    elif mode == 0x8:
        off = mem[p+1]; n += 1
        if off & 0x80: off -= 0x100
        s = f"{off},{reg}"
    elif mode == 0x9:
        off = (mem[p+1]<<8)|mem[p+2]; n += 2
        if off & 0x8000: off -= 0x10000
        s = f"{off},{reg}"
    elif mode == 0xC:
        off = mem[p+1]; n += 1
        if off & 0x80: off -= 0x100
        s = f"{off},PC"
    elif mode == 0xD:
        off = (mem[p+1]<<8)|mem[p+2]; n += 2
        s = f"{off},PC"
    elif mode == 0xF:
        addr = (mem[p+1]<<8)|mem[p+2]; n += 2
        s = f"${addr:04X}"
    else:
        s = f"?{pb:02X}"
    if ind: s = f"[{s}]"
    return s, n


def disasm_one(mem, pc, base=0):
    """Disassemble one instruction. mem indexed from 0; pc is index; base is the
    address that mem[0] represents (for branch/abs target display)."""
    op = mem[pc]
    addr = base + pc
    def b8(i): return mem[i]
    def b16(i): return (mem[i]<<8)|mem[i+1]

    if op == 0x10 or op == 0x11:
        op2 = mem[pc+1]
        # long branches and a few page-2/3 ops
        if op == 0x10 and 0x21 <= op2 <= 0x2F:
            rel = b16(pc+2)
            if rel & 0x8000: rel -= 0x10000
            mn = "L"+BR[op2-0x00] if (op2 in BR) else f"LB?{op2:02X}"
            # map to long names
            lbm = {0x21:"LBRN",0x22:"LBHI",0x23:"LBLS",0x24:"LBCC",0x25:"LBCS",
                   0x26:"LBNE",0x27:"LBEQ",0x28:"LBVC",0x29:"LBVS",0x2A:"LBPL",
                   0x2B:"LBMI",0x2C:"LBGE",0x2D:"LBLT",0x2E:"LBGT",0x2F:"LBLE"}
            return f"{lbm[op2]} ${addr+4+rel & 0xFFFF:04X}", 4
        if op == 0x10 and op2 == 0x3F: return "SWI2", 2
        if op == 0x11 and op2 == 0x3F: return "SWI3", 2
        # page2 load/store (LDY/STY/LDS/STS/CMPD/CMPY)
        p2 = {0x8E:("LDY","imm16"),0x9E:("LDY","dir"),0xAE:("LDY","idx"),0xBE:("LDY","ext"),
              0x9F:("STY","dir"),0xAF:("STY","idx"),0xBF:("STY","ext"),
              0xCE:("LDS","imm16"),0xDE:("LDS","dir"),0xEE:("LDS","idx"),0xFE:("LDS","ext"),
              0xDF:("STS","dir"),0xEF:("STS","idx"),0xFF:("STS","ext"),
              0x83:("CMPD","imm16"),0x8C:("CMPY","imm16"),0xAC:("CMPY","idx")}
        if op == 0x10 and op2 in p2:
            mn,mode = p2[op2]
            return _fmt(mem,pc+2,mn,mode,addr,2)
        return f"FCB ${op:02X} ; page", 1

    if op in INH: return INH[op], 1
    if op == 0x3C: return f"CWAI #${b8(pc+1):02X}", 2
    if op == 0x1A: return f"ORCC #${b8(pc+1):02X}", 2
    if op == 0x1C: return f"ANDCC #${b8(pc+1):02X}", 2
    if op == 0x1E or op == 0x1F:
        pb = mem[pc+1]
        mn = "EXG" if op==0x1E else "TFR"
        return f"{mn} {REGS.get(pb>>4,'?')},{REGS.get(pb&0xF,'?')}", 2
    if op in (0x34,0x35,0x36,0x37):
        pb = mem[pc+1]
        names=["CC","A","B","DP","X","Y","U/S","PC"]
        regs=[names[i] for i in range(8) if pb&(1<<i)]
        mn={0x34:"PSHS",0x35:"PULS",0x36:"PSHU",0x37:"PULU"}[op]
        return f"{mn} {','.join(regs)}", 2
    if op in BR:
        rel = b8(pc+1)
        if rel & 0x80: rel -= 0x100
        return f"{BR[op]} ${addr+2+rel & 0xFFFF:04X}", 2
    if op == 0x16:  # LBRA
        rel = b16(pc+1)
        if rel&0x8000: rel-=0x10000
        return f"LBRA ${addr+3+rel & 0xFFFF:04X}", 3
    if op == 0x17:  # LBSR
        rel = b16(pc+1)
        if rel&0x8000: rel-=0x10000
        return f"LBSR ${addr+3+rel & 0xFFFF:04X}", 3

    if op in MAIN:
        mn,mode = MAIN[op]
        return _fmt(mem,pc+1,mn,mode,addr,1)
    return f"FCB ${op:02X}", 1


def _fmt(mem, p, mn, mode, addr, opbytes):
    if mode == "imm8": return f"{mn} #${mem[p]:02X}", opbytes+1
    if mode == "imm16": return f"{mn} #${(mem[p]<<8)|mem[p+1]:04X}", opbytes+2
    if mode == "dir": return f"{mn} <${mem[p]:02X}", opbytes+1
    if mode == "ext": return f"{mn} ${(mem[p]<<8)|mem[p+1]:04X}", opbytes+2
    if mode == "idx":
        s,n = _idx(mem,p)
        return f"{mn} {s}", opbytes+n
    return f"{mn} ?", opbytes


def disasm(mem, start, count, base=0):
    pc = start
    lines = []
    for _ in range(count):
        if pc >= len(mem): break
        txt, n = disasm_one(mem, pc, base)
        raw = ' '.join(f'{mem[pc+i]:02X}' for i in range(n) if pc+i < len(mem))
        lines.append((base+pc, raw, txt))
        pc += n
    return lines
