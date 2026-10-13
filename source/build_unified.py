#!/usr/bin/env python3
"""Build the OS from the single unified source os_unified.asm (base + midiout14 block merged;
old SMSAVE/SMLOAD bodies reclaimed). Overlays $9700+ onto the D2 base disk's sector set.
Replaces build_midiout14.py: no binary patching - all changes are source edits."""
from assembler_fixed import Assembler6809
from mirage_hfe import MirageHFE
import shutil, sys

SECMAP = [(0x9600,1,0,1024),(0x9A00,1,1,1024),(0x9E00,1,2,1024),(0xA200,1,3,1024),(0xA600,1,4,1024),
          (0xAA00,1,5,512),(0xAC00,2,5,512),(0xAE00,3,5,512),(0xB000,4,5,512),(0xB200,5,5,512),
          (0xB400,6,5,512),(0xB600,7,5,512),(0xB800,8,5,512),(0xBA00,9,5,512),(0xBC00,10,5,512)]
BASE = 0x9600
ORG  = 0x9700

def build(src="os_unified.asm", d2="DSKA0000_base.hfe", out="DSKA0000_orovela.hfe"):
    asm = Assembler6809()
    code = asm.assemble(open(src, encoding="utf-8").read())
    syms = getattr(asm, 'symbols', None) or asm.labels
    end = ORG + len(code) - 1
    assert end <= 0xBDFF, f"code overflows the loadable window (ends ${end:04X} > $BDFF)"

    h0 = MirageHFE(d2)
    img = bytearray(0xBDFF - BASE + 1)
    for (a, t, s, sz) in SECMAP:
        img[a-BASE:a-BASE+sz] = h0.read_sector(t, s)
    img[ORG-BASE:] = b'\x00' * (0xBDFF - ORG + 1)   # clear the whole code window
    img[ORG-BASE:ORG-BASE+len(code)] = code          # overlay

    # --- S74: regenerate the frequency table at $9600 (128 entries, 16-bit little-endian) ---
    # The inherited table was STRETCHED: measured octave ratios 2.0252 / 2.0320 / 2.0323 / 2.0305 /
    # 2.0301 / 2.0299 instead of 2.0000, i.e. +26.6 cents per octave accumulating to +133 cents
    # across the 61-key keyboard. That is why middle C on the default wave measured ~265Hz instead
    # of 261.63 (+22 cents), why every octave A/B in the S57-S71 recordings came back at 2.02-2.04,
    # and it is a large contributor to chord beating (every interval was wrong, not just detuned).
    # Rebuilt as a true equal-tempered series anchored on the hardware measurement: entry 36 is
    # middle C, and the old 1144 played 22 cents sharp, so the anchor is 1144 * 2^(-22.2/1200).
    ANCHOR = 1144 * (2 ** (-22.2 / 1200.0))          # = 1129.5 counts at middle C (index 36)
    ftab = bytearray()
    for i in range(128):
        v = int(round(ANCHOR * (2.0 ** ((i - 36) / 12.0))))
        v = min(v, 0xFFFF)                            # top entries saturate; unreachable from the keys
        ftab += bytes((v & 0xFF, v >> 8))             # lo, hi
    img[0x9600-BASE:0x9600-BASE+256] = ftab

    # --- S108: pitch-bend slope tables in the frequency table's unreachable tail ---
    # The table has 128 entries but the keyboard can only reach index 98 (top key 74 plus two
    # octaves of transpose), so $96C6-$96FF holds saturated values nothing ever reads. Two 24-byte
    # tables fit there, costing no code space at all.
    # Bend is exponential in semitones while our offset is linear in wheel position, so each range
    # gets TWO slopes - exact at full deflection in each direction, chord-approximated between:
    #     up   fraction = 2^(N/12) - 1        down fraction = 1 - 2^(-N/12)
    # Stored as slope*64, which keeps the largest (3.0 up at N=24 -> 192) inside a byte.
    up   = bytes(min(255, round((2 ** (n / 12.0) - 1) * 64)) for n in range(1, 25))
    down = bytes(min(255, round((1 - 2 ** (-n / 12.0)) * 64)) for n in range(1, 25))
    img[0x96D0-BASE:0x96D0-BASE+24] = up
    img[0x96E8-BASE:0x96E8-BASE+24] = down

    shutil.copy(d2, out)
    hO = MirageHFE(out)
    for (a, t, s, sz) in SECMAP:
        hO.write_sector(t, s, bytes(img[a-BASE:a-BASE+sz]))
    # S214: blank all ten slot headers so a flashed disk always starts with empty slots
    # (a no-op on the clean base disk; kept for builds onto older bases).
    for s in range(10):
        hO.write_sector(11 + 6*s + 4, 5, bytes(512))
    hO.save(out)

    hV = MirageHFE(out)
    img2 = bytearray(0xBDFF - BASE + 1)
    for (a, t, s, sz) in SECMAP:
        img2[a-BASE:a-BASE+sz] = hV.read_sector(t, s)
    assert bytes(img2) == bytes(img), "code round-trip mismatch"
    print(f"built {out}: {len(code)}B  ${ORG:04X}-${end:04X}  ({0xBDFF-end} bytes free)")
    return code, syms

if __name__ == '__main__':
    import argparse, os
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Assemble os_unified.asm and write a flashable Orovela HFE.")
    ap.add_argument("out", nargs="?", default="DSKA0000_orovela.hfe", help="output .hfe path")
    ap.add_argument("--src", default=os.path.join(here, "os_unified.asm"), help="assembly source")
    ap.add_argument("--base", default=os.path.join(here, "DSKA0000_base.hfe"), help="base disk image")
    a = ap.parse_args()
    build(src=a.src, d2=a.base, out=a.out)
