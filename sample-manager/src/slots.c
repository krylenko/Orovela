/* slots.c — see slots.h */
#include "slots.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* SMTAB: 34 sectors mapping DOC $0000-$7FFF, in this exact order:
 * rel-tracks 0-3 sectors 0..5, rel-tracks 4-5 sectors 0..4. */
typedef struct { int rel_t, sec, size; } SmEnt;
static SmEnt SMTAB[34];
static int smtab_ready = 0;

static void smtab_init(void)
{
    if (smtab_ready) return;
    int n = 0;
    for (int t = 0; t < 4; t++)
        for (int s = 0; s < 6; s++)
            SMTAB[n++] = (SmEnt){t, s, s == 5 ? 512 : 1024};
    for (int t = 4; t < 6; t++)
        for (int s = 0; s < 5; s++)
            SMTAB[n++] = (SmEnt){t, s, 1024};
    smtab_ready = 1;
}

int slot_base_track(int s) { return 11 + 6 * s; }

/* v0.8: TRUE capture rates (Orovela S233c). Exact at the Mirage's 2.000 MHz E
 * clock: period = (N+1) x (latch+2) x 0.5 us for rates 1-3, one tick for rate 4.
 * v0.7's 3140 / 5831 / 9420 came from a calibration sine that was ~147 cents
 * sharp - every v0.7 export was tagged 147 c flat and every import resampled to
 * the wrong target. */
double rate_hz_exact(int rate)
{
    switch (rate) {
    case 1: return 2000000.0 / 585.0;   /*  3418.80 */
    case 2: return 2000000.0 / 315.0;   /*  6349.21 */
    case 3: return 2000000.0 / 195.0;   /* 10256.41 */
    case 4: return 2000000.0 / 129.0;   /* 15503.88 (Orovela 1.4) */
    default: return 0.0;
    }
}

int rate_to_hz(int rate)
{
    double hz = rate_hz_exact(rate);
    return hz > 0 ? (int)(hz + 0.5) : 0;
}

int smppre_to_rate(int pre)
{
    switch (pre) { case 8: return 1; case 4: return 2; case 2: return 3; case 1: return 4; }
    return 0;
}

int hdr_nparm(const uint8_t *hdr)
{
    if (hdr[0] != 0xC3 || hdr[1] != 0x3C) return 0;
    switch (hdr[2]) { case 3: return 52; case 4: return 53; case 5: return 54; }
    return 0;
}

int hdr_meta_off(const uint8_t *hdr) { return 4 + 4 * hdr_nparm(hdr); }

int hdr_param_by_spec(const uint8_t *hdr, int spec)
{
    int n = hdr_nparm(hdr);
    for (int i = 0; i < n; i++)
        if (hdr[4 + i * 4] == (uint8_t)spec)
            return hdr[4 + i * 4 + 1];
    return -1;
}

int slot_info(const HFE *h, int s, SlotInfo *si)
{
    memset(si, 0, sizeof *si);
    int size = 0, crc = 0;
    if (hfe_read_sector(h, slot_base_track(s) + 4, 5, si->header, &size, &crc) != 0
        || size != HDR_BYTES) {
        si->kind = SLOT_UNREADABLE;
        return 0;
    }
    const uint8_t *hd = si->header;
    if (hd[0] == 0x00 && hd[1] == 0x00)      si->kind = SLOT_EMPTY;
    else if (hd[0] == 0xC3 && hd[1] == 0x3C) si->kind = hdr_nparm(hd) ? SLOT_V3 : SLOT_OLDVER;
    else if (hd[0] == 0xA5 && hd[1] == 0x5A) si->kind = SLOT_ANCIENT;
    else                                     si->kind = SLOT_INVALID;

    if (si->kind == SLOT_V3) {
        si->version = hd[2];
        si->meta = hdr_meta_off(hd);
        si->has_sample = hd[3] & 1;
        /* the OS loader derives the rate from the stored prescaler N */
        int r = smppre_to_rate(hd[si->meta + 1]);
        if (!r) { int p = hdr_param_by_spec(hd, 1); r = (p >= 1 && p <= 4) ? p : 0; }
        si->rate = r;
        si->rate_hz = rate_to_hz(si->rate);
        si->loop_on = hd[si->meta + 5] != 0;  /* LMODE */
    }
    return 0;
}

int slot_read_sample(const HFE *h, int s, uint8_t *buf)
{
    smtab_init();
    int base = slot_base_track(s), off = 0;
    for (int i = 0; i < 34; i++) {
        int size = 0;
        if (hfe_read_sector(h, base + SMTAB[i].rel_t, SMTAB[i].sec,
                            buf + off, &size, NULL) != 0) return -1;
        if (size != SMTAB[i].size) return -2;
        off += size;
    }
    return (off == SAMPLE_BYTES) ? 0 : -3;
}

int slot_write_sample(HFE *h, int s, const uint8_t *buf)
{
    smtab_init();
    int base = slot_base_track(s), off = 0;
    for (int i = 0; i < 34; i++) {
        if (hfe_write_sector(h, base + SMTAB[i].rel_t, SMTAB[i].sec,
                             buf + off, SMTAB[i].size) != 0) return -1;
        off += SMTAB[i].size;
    }
    return 0;
}

int cursed_region_blank(const uint8_t *s)
{
    for (int i = 0; i < CURSED_LEN; i++)
        if (s[CURSED_OFF + i] != 0) return 0;
    return 1;
}

int slot_read_audio_playback(const HFE *h, int s, uint8_t *buf)
{
    int rc = slot_read_sample(h, s, buf);
    if (rc != 0) return rc;
    /* legacy (<=146) save: conceal exactly as the old SMLOAD2 did */
    if (cursed_region_blank(buf))
        memcpy(buf + CURSED_OFF, buf + CURSED_OFF - CURSED_LEN, CURSED_LEN);
    /* load scrub: $00 -> $01, as every OS loader does */
    for (int i = 0; i < SAMPLE_BYTES; i++)
        if (buf[i] == 0) buf[i] = 1;
    return 0;
}

int slot_write_header(HFE *h, int s, const uint8_t *hdr)
{
    return hfe_write_sector(h, slot_base_track(s) + 4, 5, hdr, HDR_BYTES);
}

int slot_clear(HFE *h, int s)
{
    uint8_t z[HDR_BYTES];
    memset(z, 0, sizeof z);
    return slot_write_header(h, s, z);
}

/* ---- .oro ------------------------------------------------------------ */

void oro_build(uint8_t *buf, const uint8_t *hdr, const uint8_t *sample)
{
    memcpy(buf, ORO_MAGIC, 4);
    memcpy(buf + 4, hdr, HDR_BYTES);
    memcpy(buf + 4 + HDR_BYTES, sample, SAMPLE_BYTES);
}

int oro_parse(const uint8_t *buf, size_t len,
              const uint8_t **hdr, const uint8_t **sample)
{
    if (len != ORO_FILE_BYTES) return -1;
    if (memcmp(buf, ORO_MAGIC, 4) != 0) return -2;
    const uint8_t *hd = buf + 4;
    if (!hdr_nparm(hd)) return -3;      /* v3, v4 or v5 program header */
    *hdr = hd;
    *sample = buf + 4 + HDR_BYTES;
    return 0;
}

static int write_file(const char *path, const uint8_t *buf, size_t n)
{
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    size_t w = fwrite(buf, 1, n, f);
    if (fclose(f) != 0 || w != n) return -2;
    return 0;
}

static uint8_t *read_file(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long ln = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (ln < 0) { fclose(f); return NULL; }
    uint8_t *buf = (uint8_t *)malloc((size_t)ln ? (size_t)ln : 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)ln, f) != (size_t)ln) { free(buf); fclose(f); return NULL; }
    fclose(f);
    *n = (size_t)ln;
    return buf;
}

int slot_export_oro(const HFE *h, int s, const char *path)
{
    SlotInfo si;
    slot_info(h, s, &si);
    if (si.kind != SLOT_V3) return -1;
    uint8_t *sample = (uint8_t *)malloc(SAMPLE_BYTES);
    uint8_t *buf = (uint8_t *)malloc(ORO_FILE_BYTES);
    if (!sample || !buf) { free(sample); free(buf); return -2; }
    if (slot_read_sample(h, s, sample) != 0) { free(sample); free(buf); return -3; }
    oro_build(buf, si.header, sample);
    int rc = write_file(path, buf, ORO_FILE_BYTES);
    free(sample); free(buf);
    return rc ? -4 : 0;
}

int slot_import_oro(HFE *h, int s, const char *path)
{
    size_t n = 0;
    uint8_t *buf = read_file(path, &n);
    if (!buf) return -1;
    const uint8_t *hdr, *sample;
    int rc = oro_parse(buf, n, &hdr, &sample);
    if (rc != 0) { free(buf); return -10 + rc; }  /* -11 size, -12 magic, -13 header */
    /* Legacy .oro (<=146 save: idx32 region all zeros): bake the old loader's
     * concealment into the disk so the sound plays under unified147 exactly
     * as it did under the OS that saved it. 147-era .oro passes verbatim. */
    uint8_t *smp = (uint8_t *)malloc(SAMPLE_BYTES);
    if (!smp) { free(buf); return -4; }
    memcpy(smp, sample, SAMPLE_BYTES);
    if (cursed_region_blank(smp)) {
        for (int i = 0; i < CURSED_LEN; i++) {
            uint8_t v = smp[CURSED_OFF - CURSED_LEN + i];
            smp[CURSED_OFF + i] = v ? v : 1;   /* SMLOAD2's conceal copy scrubbed too */
        }
    }
    /* audio first, header LAST — same interrupted-write discipline as the OS */
    if (slot_write_sample(h, s, smp) != 0) { free(smp); free(buf); return -2; }
    if (slot_write_header(h, s, hdr) != 0) { free(smp); free(buf); return -3; }
    free(smp);
    free(buf);
    return 0;
}

/* ---- WAV ------------------------------------------------------------- */

static void put32(uint8_t *p, uint32_t v) { p[0]=v; p[1]=v>>8; p[2]=v>>16; p[3]=v>>24; }
static void put16(uint8_t *p, uint16_t v) { p[0]=v; p[1]=v>>8; }

/* Build a 16-bit mono PCM WAV in memory. out must hold 44 + 2*n bytes. */
size_t wav_build_pcm16(uint8_t *out, const uint8_t *sample, int n, int hz)
{
    uint32_t dlen = (uint32_t)n * 2;
    memcpy(out, "RIFF", 4); put32(out + 4, 36 + dlen); memcpy(out + 8, "WAVE", 4);
    memcpy(out + 12, "fmt ", 4); put32(out + 16, 16);
    put16(out + 20, 1); put16(out + 22, 1);
    put32(out + 24, (uint32_t)hz); put32(out + 28, (uint32_t)hz * 2);
    put16(out + 32, 2); put16(out + 34, 16);
    memcpy(out + 36, "data", 4); put32(out + 40, dlen);
    uint8_t *p = out + 44;
    for (int i = 0; i < n; i++) {
        int16_t v = (int16_t)(((int)sample[i] - 128) << 8);
        p[0] = (uint8_t)(v & 0xFF); p[1] = (uint8_t)((v >> 8) & 0xFF); p += 2;
    }
    return 44 + dlen;
}

int slot_export_wav(const HFE *h, int s, const char *path)
{
    SlotInfo si;
    slot_info(h, s, &si);
    if (si.kind != SLOT_V3) return -1;
    int hz = si.rate_hz ? si.rate_hz : rate_to_hz(3);
    uint8_t *sample = (uint8_t *)malloc(SAMPLE_BYTES);
    uint8_t *wav = (uint8_t *)malloc(44 + 2 * SAMPLE_BYTES + 68);
    if (!sample || !wav) { free(sample); free(wav); return -2; }
    if (slot_read_audio_playback(h, s, sample) != 0) { free(sample); free(wav); return -3; }
    size_t n = wav_build_pcm16(wav, sample, SAMPLE_BYTES, hz);
    /* looped program: append a standard smpl chunk so editors/samplers see
     * the loop. LSTART/ENDPG are 512-byte pages; smpl end is INCLUSIVE. */
    if (si.loop_on) {
        int lstart = si.header[si.meta + 6], endpg = si.header[si.meta + 8];
        int unity = hdr_param_by_spec(si.header, 7);
        if (unity < 0 || unity > 127) unity = 60;
        uint8_t *c = wav + n;
        memset(c, 0, 68);
        memcpy(c, "smpl", 4);
        put32(c + 4, 60);                              /* chunk size */
        put32(c + 16, (uint32_t)(1000000000.0 / rate_hz_exact(si.rate ? si.rate : 3) + 0.5)); /* sample period ns (data+8) */
        put32(c + 20, (uint32_t)unity);                /* MIDI unity note */
        put32(c + 36, 1);                              /* one loop */
        put32(c + 44 + 4,  0);                         /* type 0 = forward */
        put32(c + 44 + 8,  (uint32_t)(lstart * 512));  /* start frame */
        put32(c + 44 + 12, (uint32_t)((endpg + 1) * 512 - 1)); /* end frame, inclusive */
        n += 68;
        put32(wav + 4, (uint32_t)(n - 8));             /* fix RIFF size */
    }
    int rc = write_file(path, wav, n);
    free(sample); free(wav);
    return rc ? -4 : 0;
}

/* ---- disk validation -------------------------------------------------- */

int disk_validate_orovela(const HFE *h)
{
    if (h->ntracks < 71) return -1;
    /* structural pass: tracks 0-70, sectors 0-5 present, right sizes, CRC ok */
    uint8_t buf[1024];
    for (int t = 0; t <= 70; t++) {
        for (int s = 0; s < 6; s++) {
            int size = 0, crc = 0;
            if (hfe_read_sector(h, t, s, buf, &size, &crc) != 0) return -1;
            if (size != (s == 5 ? 512 : 1024)) return -1;
            if (!crc) return -1;
        }
    }
    /* Orovela fingerprint: the regenerated frequency table at $9600 = (1,0).
     * 128 16-bit LE words, equal-tempered: non-decreasing over the playable
     * range, each 12 steps ~doubles.  Stock OS code there fails this. */
    int size = 0;
    if (hfe_read_sector(h, 1, 0, buf, &size, NULL) != 0 || size != 1024) return -1;
    int w[128];
    for (int i = 0; i < 128; i++) w[i] = buf[2 * i] | (buf[2 * i + 1] << 8);
    for (int i = 0; i < 97; i++)
        if (w[i + 1] < w[i]) return -2;
    for (int i = 12; i <= 60; i += 6) {
        double r = (double)w[i + 12] / (double)(w[i] ? w[i] : 1);
        if (r < 1.94 || r > 2.06) return -2;
    }
    if (w[36] < 200 || w[36] > 20000) return -2;
    return 0;
}

int disk_blank_slots(HFE *h)
{
    for (int s = 0; s < SLOT_COUNT; s++)
        if (slot_clear(h, s) != 0) return -1;
    return 0;
}
