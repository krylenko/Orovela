/* hfe.c — port of mirage_hfe.py. See hfe.h. */
#include "hfe.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int SIZES[4] = {128, 256, 512, 1024};

uint16_t crc16_ccitt(const uint8_t *data, size_t n, uint16_t crc)
{
    for (size_t i = 0; i < n; i++) {
        crc ^= (uint16_t)(data[i] << 8);
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021)
                                 : (uint16_t)(crc << 1);
    }
    return crc;
}

int hfe_from_mem(HFE *h, const uint8_t *buf, size_t len)
{
    memset(h, 0, sizeof *h);
    if (len < 1024 || memcmp(buf, "HXCPICFE", 8) != 0) return -1;
    h->d = (uint8_t *)malloc(len);
    if (!h->d) return -2;
    memcpy(h->d, buf, len);
    h->len = len;
    h->ntracks = buf[9];
    h->nsides  = buf[10];
    h->lut_off = (uint32_t)(buf[18] | (buf[19] << 8)) * 512u;
    if (h->lut_off + 4u * (uint32_t)h->ntracks > len) { hfe_free(h); return -3; }
    return 0;
}

int hfe_load(HFE *h, const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return -10;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0) { fclose(f); return -11; }
    uint8_t *buf = (uint8_t *)malloc((size_t)n);
    if (!buf) { fclose(f); return -12; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return -13; }
    fclose(f);
    int rc = hfe_from_mem(h, buf, (size_t)n);
    free(buf);
    return rc;
}

int hfe_save(const HFE *h, const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return -20;
    size_t w = fwrite(h->d, 1, h->len, f);
    if (fclose(f) != 0 || w != h->len) return -21;
    return 0;
}

void hfe_free(HFE *h)
{
    free(h->d);
    memset(h, 0, sizeof *h);
}

/* ---- track scanning ------------------------------------------------- */

typedef struct {
    long     te;      /* raw-bit index of the byte after the data-mark A1 run */
    int      size;    /* sector payload size */
    int      found;
} SecLoc;

typedef struct {
    SecLoc   sec[6];
    long    *idx;     /* side-0 global byte indices into h->d */
    long     nidx;
    uint8_t *bits;    /* raw bit array, LSB-first per byte */
    long     nbits;
} TrackScan;

static void ts_free(TrackScan *ts)
{
    free(ts->idx);
    free(ts->bits);
    memset(ts, 0, sizeof *ts);
}

static int track_span(const HFE *h, int t, long *goff, long *ln)
{
    if (t < 0 || t >= h->ntracks) return -1;
    const uint8_t *e = h->d + h->lut_off + 4u * (uint32_t)t;
    long off = e[0] | (e[1] << 8);
    long l   = e[2] | (e[3] << 8);
    *goff = off * 512;
    *ln = l;
    if (*goff + *ln > (long)h->len) return -2;
    return 0;
}

/* Decode n MFM bytes starting at raw-bit index sb: data bits are at odd cells. */
static void mfm_decode(const uint8_t *bits, long sb, int n, uint8_t *out)
{
    long pos = sb;
    for (int k = 0; k < n; k++) {
        int v = 0;
        for (int b = 0; b < 8; b++) { v = (v << 1) | bits[pos + 1]; pos += 2; }
        out[k] = (uint8_t)v;
    }
}

static int scan_track(const HFE *h, int t, TrackScan *ts)
{
    memset(ts, 0, sizeof *ts);
    long goff, ln;
    if (track_span(h, t, &goff, &ln) != 0) return -1;

    /* side-0 byte indices: first 256 bytes of every 512-byte block */
    ts->idx = (long *)malloc(sizeof(long) * (size_t)(ln / 2 + 256));
    if (!ts->idx) return -2;
    ts->nidx = 0;
    for (long i = 0; i < ln; i += 512) {
        long m = ln - i; if (m > 256) m = 256;
        for (long j = 0; j < m; j++) ts->idx[ts->nidx++] = goff + i + j;
    }

    ts->nbits = ts->nidx * 8;
    ts->bits = (uint8_t *)malloc((size_t)ts->nbits + 64);
    if (!ts->bits) { ts_free(ts); return -3; }
    for (long k = 0; k < ts->nidx; k++) {
        uint8_t byte = h->d[ts->idx[k]];
        for (int b = 0; b < 8; b++) ts->bits[k * 8 + b] = (byte >> b) & 1;
    }

    /* find A1 sync words (0x4489 in the raw stream) */
    long *a1 = (long *)malloc(sizeof(long) * 4096);
    if (!a1) { ts_free(ts); return -4; }
    long na1 = 0;
    unsigned val = 0;
    for (long i = 0; i < ts->nbits; i++) {
        val = ((val << 1) | ts->bits[i]) & 0xFFFF;
        if (val == 0x4489 && na1 < 4096) a1[na1++] = i;
    }

    int pend_sec = -1, pend_size = -1;
    long i = 0;
    while (i < na1) {
        if (i + 2 < na1 && a1[i + 1] - a1[i] == 16 && a1[i + 2] - a1[i + 1] == 16) {
            long te = a1[i + 2] + 1;
            uint8_t mark;
            if (te + 16 > ts->nbits) break;
            mfm_decode(ts->bits, te, 1, &mark);
            if (mark == 0xFE) {
                uint8_t idf[7];
                if (te + 7 * 16 <= ts->nbits) {
                    mfm_decode(ts->bits, te, 7, idf);
                    pend_sec = idf[3];
                    pend_size = idf[4] & 3;
                }
            } else if (mark == 0xFB || mark == 0xF8) {
                if (pend_sec >= 0 && pend_sec < 6) {
                    ts->sec[pend_sec].te = te;
                    ts->sec[pend_sec].size = SIZES[pend_size];
                    ts->sec[pend_sec].found = 1;
                }
                pend_sec = -1;
            }
            i += 3;
        } else {
            i += 1;
        }
    }
    free(a1);
    return 0;
}

int hfe_read_sector(const HFE *h, int track, int sector,
                    uint8_t *out, int *size, int *crc_ok)
{
    if (sector < 0 || sector > 5) return -1;
    TrackScan ts;
    if (scan_track(h, track, &ts) != 0) return -2;
    if (!ts.sec[sector].found) { ts_free(&ts); return -3; }
    long te = ts.sec[sector].te;
    int sz = ts.sec[sector].size;
    if (te + (long)(1 + sz + 2) * 16 > ts.nbits) { ts_free(&ts); return -4; }

    uint8_t *blob = (uint8_t *)malloc((size_t)(1 + sz + 2));
    if (!blob) { ts_free(&ts); return -5; }
    mfm_decode(ts.bits, te, 1 + sz + 2, blob);
    memcpy(out, blob + 1, (size_t)sz);
    if (size) *size = sz;
    if (crc_ok) {
        static const uint8_t A1[3] = {0xA1, 0xA1, 0xA1};
        uint16_t crc = crc16_ccitt(A1, 3, 0xFFFF);
        crc = crc16_ccitt(blob, (size_t)(1 + sz), crc);
        uint16_t stored = (uint16_t)((blob[1 + sz] << 8) | blob[1 + sz + 1]);
        *crc_ok = (crc == stored);
    }
    free(blob);
    ts_free(&ts);
    return 0;
}

int hfe_write_sector(HFE *h, int track, int sector,
                     const uint8_t *payload, int len)
{
    if (sector < 0 || sector > 5) return -1;
    TrackScan ts;
    if (scan_track(h, track, &ts) != 0) return -2;
    if (!ts.sec[sector].found) { ts_free(&ts); return -3; }
    long te = ts.sec[sector].te;
    int sz = ts.sec[sector].size;
    if (len != sz) { ts_free(&ts); return -4; }

    uint8_t mark;
    mfm_decode(ts.bits, te, 1, &mark);

    int fl = 1 + sz + 2;
    uint8_t *full = (uint8_t *)malloc((size_t)fl);
    if (!full) { ts_free(&ts); return -5; }
    full[0] = mark;
    memcpy(full + 1, payload, (size_t)sz);
    static const uint8_t A1[3] = {0xA1, 0xA1, 0xA1};
    uint16_t crc = crc16_ccitt(A1, 3, 0xFFFF);
    crc = crc16_ccitt(full, (size_t)(1 + sz), crc);
    full[1 + sz] = (uint8_t)(crc >> 8);
    full[1 + sz + 1] = (uint8_t)(crc & 0xFF);

    if (te + (long)fl * 16 > ts.nbits) { free(full); ts_free(&ts); return -6; }

    /* MFM-encode mark+payload+crc cells, clock continuity from preceding cell */
    int prev_data = (te > 0) ? ts.bits[te - 1] : 0;
    long pos = te;
    for (int k = 0; k < fl; k++) {
        uint8_t byte = full[k];
        for (int bi = 7; bi >= 0; bi--) {
            int dbit = (byte >> bi) & 1;
            int cbit = (prev_data == 0 && dbit == 0) ? 1 : 0;
            ts.bits[pos] = (uint8_t)cbit;
            ts.bits[pos + 1] = (uint8_t)dbit;
            prev_data = dbit;
            pos += 2;
        }
    }
    /* commit raw bits back into the file image */
    for (long rb = te; rb < pos; rb++) {
        long gi = ts.idx[rb / 8];
        int bit = (int)(rb % 8);
        if (ts.bits[rb]) h->d[gi] |= (uint8_t)(1 << bit);
        else             h->d[gi] &= (uint8_t)~(1 << bit);
    }
    free(full);
    ts_free(&ts);
    return 0;
}
