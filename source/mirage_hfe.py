"""Mirage HFE toolkit: decode sectors, surgically edit sector bytes in the raw
MFM bitstream (preserving all gaps/sync/timing), recompute CRCs, write HFE.

Verified against the known-good working disk DSKA0000.hfe.
"""
import struct

SIZES = {0: 128, 1: 256, 2: 512, 3: 1024}


def crc16_ccitt(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if (crc & 0x8000) else (crc << 1)
            crc &= 0xFFFF
    return crc


class MirageHFE:
    def __init__(self, path):
        self.d = bytearray(open(path, 'rb').read())
        assert self.d[:8] == b'HXCPICFE', "not an HFE file"
        self.ntracks = self.d[9]
        self.nsides = self.d[10]
        # track LUT lives at block given by header word at 0x12, but for these disks it's block 1 (byte 512)
        self.lut_off = struct.unpack('<H', self.d[18:20])[0] * 512

    def _track_span(self, t):
        e = self.d[self.lut_off + t * 4: self.lut_off + t * 4 + 4]
        off, ln = struct.unpack('<HH', e)
        return off * 512, ln

    def _side0_indices(self, goff, ln):
        idx = []
        for i in range(0, ln, 512):
            for j in range(min(256, ln - i)):
                idx.append(goff + i + j)
        return idx

    def _bits(self, idx):
        b = bytearray()
        for gi in idx:
            byte = self.d[gi]
            for i in range(8):
                b.append((byte >> i) & 1)
        return b

    @staticmethod
    def _decode(bits, sb, n):
        out = bytearray(); pos = sb
        for _ in range(n):
            v = 0
            for _b in range(8):
                v = (v << 1) | bits[pos + 1]; pos += 2
            out.append(v)
        return bytes(out), pos

    @staticmethod
    def _find(bits, pat):
        r = []; val = 0
        for i, b in enumerate(bits):
            val = ((val << 1) | b) & 0xFFFF
            if val == pat:
                r.append(i)
        return r

    def _scan_track(self, t):
        """Return dict sector_num -> (data_mark_rawbit, size, idx_list)."""
        goff, ln = self._track_span(t)
        idx = self._side0_indices(goff, ln)
        bits = self._bits(idx)
        a1 = self._find(bits, 0x4489)
        res = {}; i = 0; pend = None
        while i < len(a1):
            if i + 2 < len(a1) and a1[i + 1] - a1[i] == 16 and a1[i + 2] - a1[i + 1] == 16:
                te = a1[i + 2] + 1
                mk, _ = self._decode(bits, te, 1); m = mk[0]
                if m == 0xFE:
                    idf, _ = self._decode(bits, te, 7)
                    pend = (idf[3], idf[4])  # sector num, size code
                elif m in (0xFB, 0xF8):
                    if pend:
                        res[pend[0]] = (te, SIZES[pend[1]], idx)
                        pend = None
                i += 3
            else:
                i += 1
        return res, bits

    def read_sector(self, t, s):
        scan, bits = self._scan_track(t)
        te, sz, idx = scan[s]
        blob, _ = self._decode(bits, te, 1 + sz + 2)
        return blob[1:1 + sz]

    def read_linear(self):
        out = bytearray()
        for t in range(80):
            scan, bits = self._scan_track(t)
            for s in [0, 1, 2, 3, 4, 5]:
                te, sz, idx = scan[s]
                blob, _ = self._decode(bits, te, 1 + sz + 2)
                out += blob[1:1 + sz]
        return bytes(out)

    def write_sector(self, t, s, new_payload):
        """Rewrite a sector's payload in place: re-encode MFM data cells and CRC,
        leaving everything else (gaps, sync, ID fields) untouched."""
        scan, bits = self._scan_track(t)
        te, sz, idx = scan[s]
        assert len(new_payload) == sz, f"payload must be {sz} bytes, got {len(new_payload)}"
        mark, _ = self._decode(bits, te, 1)
        full = bytes([mark[0]]) + bytes(new_payload)
        crc = crc16_ccitt(bytes([0xA1, 0xA1, 0xA1]) + full)
        full += bytes([(crc >> 8) & 0xFF, crc & 0xFF])
        # encode bytes starting at payload (skip mark = first byte of `full`)
        # We re-encode mark+payload+crc cells with proper MFM clocking.
        self._encode_field(bits, idx, te, full)

    def _encode_field(self, bits, idx, start_bit, data_bytes):
        """MFM-encode data_bytes into the raw bit array starting at start_bit,
        using standard MFM rule with continuity from the preceding cell, then
        commit changed raw bits back into self.d."""
        # Determine previous data bit (for clock rule) from the cell before start_bit.
        prev_data = bits[start_bit - 1] if start_bit > 0 else 0
        pos = start_bit
        changed_bytes = {}
        for byte in data_bytes:
            for bi in range(7, -1, -1):
                dbit = (byte >> bi) & 1
                # MFM: clock bit = 1 if previous data bit == 0 and current data bit == 0
                cbit = 1 if (prev_data == 0 and dbit == 0) else 0
                # write clock then data
                if bits[pos] != cbit:
                    bits[pos] = cbit
                if bits[pos + 1] != dbit:
                    bits[pos + 1] = dbit
                prev_data = dbit
                pos += 2
        # commit ALL raw bits in this field range back to d (simplest & safe)
        for rb in range(start_bit, pos):
            gi = idx[rb // 8]
            bit = rb % 8
            if bits[rb]:
                self.d[gi] |= (1 << bit)
            else:
                self.d[gi] &= ~(1 << bit)

    def save(self, path):
        open(path, 'wb').write(self.d)


if __name__ == '__main__':
    h = MirageHFE('DSKA0000.hfe')
    lin = h.read_linear()
    ref = open('disk_linear.bin', 'rb').read()
    print('round-trip read matches reference:', lin == ref, len(lin))
