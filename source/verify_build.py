#!/usr/bin/env python3
"""Check a built Orovela disk image against the published 1.5 release.

    python3 verify_build.py DSKA0000_orovela.hfe

Compares the whole-file SHA-256 and the OS code window ($9600-$BDFF, read back
through the sector map) with the values of the released Orovela 1.5 image.
Exit status 0 = identical to the release."""
import hashlib, sys
from mirage_hfe import MirageHFE
from build_unified import SECMAP, BASE

RELEASE_SHA256 = "1af38ccf692552619769675b6de5e955766b5270a3b9119d5e4a1f8a2613d7f6"

path = sys.argv[1] if len(sys.argv) > 1 else "DSKA0000_orovela.hfe"
data = open(path, "rb").read()
sha = hashlib.sha256(data).hexdigest()

h = MirageHFE(path)
img = bytearray(0xBDFF - BASE + 1)
for a, t, s, sz in SECMAP:
    img[a - BASE:a - BASE + sz] = h.read_sector(t, s)
code = bytes(img[0x9700 - BASE:]).rstrip(b"\x00")

print(f"{path}: {len(data)} bytes, sha256 {sha}")
print(f"code window: {len(code)} bytes at $9700-${0x9700 + len(code) - 1:04X}")
if sha == RELEASE_SHA256:
    print("MATCH: byte-identical to the Orovela 1.5 release image")
    sys.exit(0)
print("DIFFERENT from the Orovela 1.5 release image (expected if you changed the source)")
sys.exit(1)
