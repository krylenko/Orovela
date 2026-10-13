import re
import struct


class Assembler6809:
    MN = {
        "NOP","RTS","RTI","SWI","SWI2","SWI3","DAA","SEX","ABX","MUL",
        "NEGA","COMA","LSRA","RORA","ASRA","ASLA","LSLA","ROLA","DECA","INCA","TSTA","CLRA",
        "NEGB","COMB","LSRB","RORB","ASRB","ASLB","LSLB","ROLB","DECB","INCB","TSTB","CLRB",
        "SYNC","CWAI","ANDCC","ORCC","EXG","TFR","PSHS","PULS","PSHU","PULU",
        "BRA","BRN","BHI","BLS","BCC","BCS","BHS","BLO","BNE","BEQ","BVC","BVS","BPL","BMI",
        "BGE","BLT","BGT","BLE","BSR","LBSR","LBRA","LBRN","LBHI","LBLS","LBCC",
        "LBCS","LBHS","LBLO","LBNE","LBEQ","LBVC","LBVS","LBPL","LBMI","LBGE","LBLT","LBGT","LBLE",
        "JSR","JMP","LEAX","LEAY","LEAS","LEAU",
        "LDA","LDB","LDD","LDX","LDY","LDS","LDU",
        "STA","STB","STD","STX","STY","STS","STU",
        "ADDA","ADDB","ADDD","ADCA","ADCB","SUBA","SUBB","SUBD","SBCA","SBCB",
        "ANDA","ANDB","ORA","ORB","EORA","EORB","BITA","BITB",
        "CMPA","CMPB","CMPD","CMPX","CMPY","CMPS","CMPU",
        "NEG","COM","LSR","ROR","ASR","ASL","LSL","ROL","DEC","INC","TST","CLR",
    }
    DR = {"ORG","EQU","FCB","FDB","FCC","RMB","END","SETDP"}
    IRB = {"X": 0, "Y": 32, "U": 64, "S": 96}

    def __init__(self):
        self.output = bytearray()
        self.labels = {}
        self.fixups = []
        self.origin = 0
        self.pc = 0
        self.pass_num = 1
        self.listing = []
        self.errors = []

    def assemble(self, source):
        for pn in (1, 2):
            self.pass_num = pn
            self.output = bytearray()
            self.fixups = []
            self.listing = []
            self.pc = self.origin
            for lineno, raw in enumerate(source.split("\n"), 1):
                try:
                    self._line(raw, lineno)
                except Exception as e:
                    self.errors.append("L{}: {} | {!r}".format(lineno, e, raw.strip()))
            if pn == 2:
                self._apply_fixups()
        if self.errors:
            raise RuntimeError("assembly failed:\n" + "\n".join(self.errors))
        return bytes(self.output)

    def _expr(self, s):
        s = s.strip()
        if not s:
            raise ValueError("empty expression")
        s2 = re.sub(r'\$([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), s)
        s2 = re.sub(r'%([01]+)', lambda m: str(int(m.group(1), 2)), s2)
        s2 = re.sub(r"'(.)'", lambda m: str(ord(m.group(1))), s2)
        def repl(m):
            n = m.group(0)
            if n in self.labels:
                return str(self.labels[n])
            if self.pass_num == 2:
                raise ValueError("Undefined label: {!r}".format(n))
            return "0x1234"
        s2 = re.sub(r'[A-Za-z_]\w*', repl, s2)
        return int(eval(s2, {"__builtins__": {}}))

    def _emit(self, *bs):
        for b in bs:
            self.output.append(b & 0xFF)
            self.pc += 1

    def _resolve(self, s):
        try:
            return self._expr(s), True
        except Exception:
            if self.pass_num == 1:
                return 0, False
            raise

    def _apply_fixups(self):
        for off, label, ftype, pc in self.fixups:
            try:
                target = self._expr(label)
            except Exception:
                self.errors.append("Unresolved fixup: {!r}".format(label))
                continue
            if ftype == "rel8":
                rel = target - pc
                if not -128 <= rel <= 127:
                    self.errors.append("Branch out of range to {!r}: offset={}".format(label, rel))
                self.output[off] = rel & 0xFF
            elif ftype == "rel16":
                rel = target - pc
                self.output[off] = (rel >> 8) & 0xFF
                self.output[off + 1] = rel & 0xFF
            elif ftype == "abs16":
                self.output[off] = (target >> 8) & 0xFF
                self.output[off + 1] = target & 0xFF
            elif ftype == "abs8":
                self.output[off] = target & 0xFF

    def _line(self, raw, lineno):
        line = re.sub(r';.*$', '', raw).rstrip()
        if not line.strip():
            return
        label = None
        rest = line
        m = re.match(r'^([A-Za-z_]\w*)(:?)\s*(.*)', line)
        indented = raw[:1] in (' ', '\t')
        if m:
            tok = m.group(1).upper()
            has_colon = m.group(2) == ':'
            after = m.group(3).strip()
            if indented and not has_colon and tok not in self.MN and tok not in self.DR:
                raise ValueError("unknown mnemonic {!r} (indented lines must start with a known instruction or directive)".format(m.group(1)))
            if has_colon or (tok not in self.MN and tok not in self.DR):
                label = m.group(1)
                rest = after
        if label:
            if self.pass_num == 1:
                m2 = re.match(r'^EQU\s+(.*)', rest, re.IGNORECASE)
                if m2:
                    try:
                        self.labels[label] = self._expr(m2.group(1))
                    except Exception:
                        self.labels[label] = 0
                    rest = ''
                else:
                    self.labels[label] = self.pc
            else:
                if re.match(r'^EQU\s', rest, re.IGNORECASE):
                    rest = ''
        rest = rest.strip()
        if not rest:
            return
        parts = rest.split(None, 1)
        mnem = parts[0].upper()
        operand = parts[1].strip() if len(parts) > 1 else ''
        s_off = len(self.output)
        s_pc = self.pc
        self._instruction(mnem, operand, lineno)
        if self.pass_num == 2:
            self.listing.append((s_pc, bytes(self.output[s_off:]), rest))

    def _decode_idx(self, op):
        op = op.strip()
        indirect = op.startswith('[') and op.endswith(']')
        if indirect:
            op = op[1:-1].strip()
        ind = 0x10 if indirect else 0
        for reg, rb in self.IRB.items():
            if op == ',{}++'.format(reg):
                return bytes([0x81 | rb | ind])
            if op == ',{}+'.format(reg):
                return bytes([0x80 | rb | ind])
            if op == ',--{}'.format(reg):
                return bytes([0x83 | rb | ind])
            if op == ',-{}'.format(reg):
                return bytes([0x82 | rb | ind])
            if op == ',{}'.format(reg) and not indirect:
                return bytes([0x84 | rb])
        m = re.match(r'^(.*),([XYUSxyus]|PC|pc)$', op)
        if m:
            off_str = m.group(1).strip()
            reg = m.group(2).upper()
            rb = self.IRB.get(reg, 0)
            if off_str.upper() == 'A':
                return bytes([0x86 | rb | ind])
            if off_str.upper() == 'B':
                return bytes([0x85 | rb | ind])
            if off_str.upper() == 'D':
                return bytes([0x8B | rb | ind])
            if reg == 'PC':
                v = self._expr(off_str)
                if -128 <= v <= 127:
                    return bytes([0x8C | ind, v & 0xFF])
                return bytes([0x8D | ind]) + struct.pack('>h', v)
            v = self._expr(off_str)
            if -16 <= v <= 15 and not indirect:
                return bytes([rb | (v & 0x1F)])
            if -128 <= v <= 127:
                return bytes([0x88 | rb | ind, v & 0xFF])
            return bytes([0x89 | rb | ind]) + struct.pack('>h', v)
        if indirect:
            v = self._expr(op)
            return bytes([0x9F]) + struct.pack('>H', v)
        raise ValueError("Cannot decode indexed operand: {!r}".format(op))

    def _instruction(self, mnem, operand, lineno):
        if mnem == 'ORG':
            v = self._expr(operand); self.pc = v; self.origin = v; return
        if mnem in ('EQU', 'END', 'SETDP'): return
        if mnem == 'FCB':
            for p in operand.split(','):
                self._emit(self._expr(p.strip()))
            return
        if mnem == 'FDB':
            for p in operand.split(','):
                v, k = self._resolve(p.strip())
                off = len(self.output)
                self._emit((v >> 8) & 0xFF, v & 0xFF)
                if not k: self.fixups.append((off, p.strip(), 'abs16', self.pc))
            return
        if mnem == 'FCC':
            m = re.match(r'["\'](.*)["\']\s*$', operand)
            if m:
                for c in m.group(1): self._emit(ord(c))
            return
        if mnem == 'RMB':
            for _ in range(self._expr(operand)): self._emit(0); return
        INH = {
            'NOP':0x12,'SYNC':0x13,'DAA':0x19,'SEX':0x1D,'RTS':0x39,'ABX':0x3A,
            'RTI':0x3B,'MUL':0x3D,'SWI':0x3F,
            'NEGA':0x40,'COMA':0x43,'LSRA':0x44,'RORA':0x46,'ASRA':0x47,
            'ASLA':0x48,'LSLA':0x48,'ROLA':0x49,'DECA':0x4A,'INCA':0x4C,'TSTA':0x4D,'CLRA':0x4F,
            'NEGB':0x50,'COMB':0x53,'LSRB':0x54,'RORB':0x56,'ASRB':0x57,
            'ASLB':0x58,'LSLB':0x58,'ROLB':0x59,'DECB':0x5A,'INCB':0x5C,'TSTB':0x5D,'CLRB':0x5F,
        }
        if mnem in INH and not operand: self._emit(INH[mnem]); return
        if mnem == 'SWI2': self._emit(0x10,0x3F); return
        if mnem == 'SWI3': self._emit(0x11,0x3F); return
        REGS = {'D':0,'X':1,'Y':2,'U':3,'S':4,'PC':5,'A':8,'B':9,'CC':10,'DP':11}
        if mnem in ('EXG','TFR'):
            opc = 0x1E if mnem=='EXG' else 0x1F
            ps = [r.strip().upper() for r in operand.split(',')]
            self._emit(opc,(REGS.get(ps[0],0)<<4)|REGS.get(ps[1],0)); return
        PSH_R = {'CC':1,'A':2,'B':4,'DP':8,'X':16,'Y':32,'U':64,'S':64,'PC':128}
        PSH_OPS = {'PSHS':0x34,'PULS':0x35,'PSHU':0x36,'PULU':0x37}
        if mnem in PSH_OPS:
            pb = 0
            for r in re.split(r'[,\s]+', operand.strip()): pb |= PSH_R.get(r.upper().strip(),0)
            self._emit(PSH_OPS[mnem],pb); return
        if mnem in ('ANDCC','ORCC','CWAI'):
            self._emit({'ANDCC':0x1C,'ORCC':0x1A,'CWAI':0x3C}[mnem],self._expr(operand.lstrip('#'))); return
        B8 = {'BRA':0x20,'BRN':0x21,'BHI':0x22,'BLS':0x23,'BCC':0x24,'BCS':0x25,'BHS':0x24,'BLO':0x25,
              'BNE':0x26,'BEQ':0x27,'BVC':0x28,'BVS':0x29,'BPL':0x2A,'BMI':0x2B,
              'BGE':0x2C,'BLT':0x2D,'BGT':0x2E,'BLE':0x2F,'BSR':0x8D}
        B16 = {'LBRA':0x16,'LBSR':0x17,'LBRN':0x21,'LBHI':0x22,'LBLS':0x23,
               'LBCC':0x24,'LBCS':0x25,'LBHS':0x24,'LBLO':0x25,'LBNE':0x26,'LBEQ':0x27,'LBVC':0x28,
               'LBVS':0x29,'LBPL':0x2A,'LBMI':0x2B,'LBGE':0x2C,'LBLT':0x2D,
               'LBGT':0x2E,'LBLE':0x2F}
        if mnem in B8:
            target,known = self._resolve(operand)
            self._emit(B8[mnem]); off = len(self.output)
            rel = (target-(self.pc+1)) if known else 0
            if known and self.pass_num == 2 and not -128 <= rel <= 127:
                self.errors.append("Branch {} out of range to {!r}: offset={} (use long branch or JMP)".format(mnem, operand, rel))
            self._emit(rel&0xFF)
            if not known: self.fixups.append((off,operand,'rel8',self.pc))
            return
        if mnem in B16:
            opc = B16[mnem]
            if mnem in ('LBRA','LBSR'):
                target,known = self._resolve(operand); self._emit(opc); off = len(self.output)
                rel = (target-(self.pc+2)) if known else 0; self._emit((rel>>8)&0xFF,rel&0xFF)
                if not known: self.fixups.append((off,operand,'rel16',self.pc))
            else:
                self._emit(0x10,opc); target,known = self._resolve(operand); off = len(self.output)
                rel = (target-(self.pc+2)) if known else 0; self._emit((rel>>8)&0xFF,rel&0xFF)
                if not known: self.fixups.append((off,operand,'rel16',self.pc))
            return
        LEA = {'LEAX':0x30,'LEAY':0x31,'LEAS':0x32,'LEAU':0x33}
        if mnem in LEA:
            pb = self._decode_idx(operand); self._emit(LEA[mnem])
            for b in pb: self._emit(b)
            return
        PAGE2 = {'LDY','STY','CMPY','LDS','STS','CMPD'}
        PAGE3 = {'CMPU','CMPS'}
        OT = {
            'LDA':(0x86,None,0x96,0xA6,0xB6),'STA':(None,None,0x97,0xA7,0xB7),
            'ADDA':(0x8B,None,0x9B,0xAB,0xBB),'ADCA':(0x89,None,0x99,0xA9,0xB9),
            'SUBA':(0x80,None,0x90,0xA0,0xB0),'SBCA':(0x82,None,0x92,0xA2,0xB2),
            'ANDA':(0x84,None,0x94,0xA4,0xB4),'ORA':(0x8A,None,0x9A,0xAA,0xBA),
            'EORA':(0x88,None,0x98,0xA8,0xB8),'BITA':(0x85,None,0x95,0xA5,0xB5),
            'CMPA':(0x81,None,0x91,0xA1,0xB1),
            'LDB':(0xC6,None,0xD6,0xE6,0xF6),'STB':(None,None,0xD7,0xE7,0xF7),
            'ADDB':(0xCB,None,0xDB,0xEB,0xFB),'ADCB':(0xC9,None,0xD9,0xE9,0xF9),
            'SUBB':(0xC0,None,0xD0,0xE0,0xF0),'SBCB':(0xC2,None,0xD2,0xE2,0xF2),
            'ANDB':(0xC4,None,0xD4,0xE4,0xF4),'ORB':(0xCA,None,0xDA,0xEA,0xFA),
            'EORB':(0xC8,None,0xD8,0xE8,0xF8),'BITB':(0xC5,None,0xD5,0xE5,0xF5),
            'CMPB':(0xC1,None,0xD1,0xE1,0xF1),
            'LDD':(None,0xCC,0xDC,0xEC,0xFC),'STD':(None,None,0xDD,0xED,0xFD),
            'ADDD':(None,0xC3,0xD3,0xE3,0xF3),'SUBD':(None,0x83,0x93,0xA3,0xB3),
            'LDX':(None,0x8E,0x9E,0xAE,0xBE),'STX':(None,None,0x9F,0xAF,0xBF),
            'CMPX':(None,0x8C,0x9C,0xAC,0xBC),
            'LDY':(None,0x8E,0x9E,0xAE,0xBE),'STY':(None,None,0x9F,0xAF,0xBF),
            'CMPY':(None,0x8C,0x9C,0xAC,0xBC),
            'LDU':(None,0xCE,0xDE,0xEE,0xFE),'STU':(None,None,0xDF,0xEF,0xFF),
            'LDS':(None,0xCE,0xDE,0xEE,0xFE),'STS':(None,None,0xDF,0xEF,0xFF),
            'CMPD':(None,0x83,0x93,0xA3,0xB3),'CMPU':(None,0x83,0x93,0xA3,0xB3),
            'CMPS':(None,0x8C,0x9C,0xAC,0xBC),
            'NEG':(None,None,0x00,0x60,0x70),'COM':(None,None,0x03,0x63,0x73),
            'LSR':(None,None,0x04,0x64,0x74),'ROR':(None,None,0x06,0x66,0x76),
            'ASR':(None,None,0x07,0x67,0x77),'ASL':(None,None,0x08,0x68,0x78),
            'LSL':(None,None,0x08,0x68,0x78),'ROL':(None,None,0x09,0x69,0x79),
            'DEC':(None,None,0x0A,0x6A,0x7A),'INC':(None,None,0x0C,0x6C,0x7C),
            'TST':(None,None,0x0D,0x6D,0x7D),'CLR':(None,None,0x0F,0x6F,0x7F),
            'JMP':(None,None,0x0E,0x6E,0x7E),'JSR':(None,None,0x9D,0xAD,0xBD),
        }
        IS16 = {'LDD','STD','ADDD','SUBD','LDX','STX','CMPX','LDY','STY','CMPY',
                'LDU','STU','LDS','STS','CMPD','CMPU','CMPS'}
        if mnem in OT:
            imm8,imm16,dir_op,idx_op,ext_op = OT[mnem]
            prefix = [0x10] if mnem in PAGE2 else ([0x11] if mnem in PAGE3 else [])
            op_str = operand.strip(); is16 = mnem in IS16
            if op_str.startswith('#'):
                v = self._expr(op_str[1:])
                if is16:
                    if imm16 is None: raise ValueError("No IMM16 for {}".format(mnem))
                    for b in prefix: self._emit(b)
                    self._emit(imm16,(v>>8)&0xFF,v&0xFF)
                else:
                    if imm8 is None: raise ValueError("No IMM8 for {}".format(mnem))
                    for b in prefix: self._emit(b)
                    self._emit(imm8,v&0xFF)
                return
            if op_str.startswith('<'):
                v = self._expr(op_str[1:])
                if dir_op is None: raise ValueError("No DIR for {}".format(mnem))
                for b in prefix: self._emit(b)
                self._emit(dir_op,v&0xFF); return
            if ',' in op_str or op_str.startswith('['):
                if idx_op is None: raise ValueError("No IDX for {}".format(mnem))
                pb = self._decode_idx(op_str)
                for b in prefix: self._emit(b)
                self._emit(idx_op)
                for b in pb: self._emit(b)
                return
            v,known = self._resolve(op_str)
            if not known: v = 0x1234
            if v <= 0xFF and dir_op is not None and not op_str.startswith('>'):
                for b in prefix: self._emit(b)
                self._emit(dir_op,v&0xFF)
                if not known: self.fixups.append((len(self.output)-1,op_str,'abs8',self.pc))
            else:
                if ext_op is None: raise ValueError("No EXT for {}".format(mnem))
                for b in prefix: self._emit(b)
                self._emit(ext_op); off = len(self.output)
                self._emit((v>>8)&0xFF,v&0xFF)
                if not known: self.fixups.append((off,op_str,'abs16',self.pc))
            return
        raise ValueError("Unknown mnemonic: {!r}".format(mnem))
