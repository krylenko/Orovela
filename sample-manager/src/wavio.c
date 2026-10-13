/* wavio.c — see wavio.h */
#include "wavio.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include "param_defaults.h"

static uint32_t rd32(const uint8_t *p) { return p[0] | (p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24); }
static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1]<<8)); }

/* exact inverse of the OS's SCALE99>>2 page mapping: page = (v*41)>>6 */
static int page_to_param(int page)
{
    int v = (64 * page + 40) / 41;
    if (v > 99) v = 99;
    if (v < 0) v = 0;
    return v;
}

int wav_import_build(const uint8_t *wav, size_t len, WavImport *o)
{
    return wav_import_build_rate(wav, len, 0, o);
}

int wav_import_build_rate(const uint8_t *wav, size_t len, int force_rate, WavImport *o)
{
    memset(o, 0, sizeof *o);
    o->unity = -1;
    if (len < 44 || memcmp(wav, "RIFF", 4) || memcmp(wav + 8, "WAVE", 4)) return -1;

    const uint8_t *fmt = NULL, *data = NULL, *smpl = NULL;
    uint32_t fmt_len = 0, data_len = 0, smpl_len = 0;
    size_t p = 12;
    while (p + 8 <= len) {
        const uint8_t *id = wav + p;
        uint32_t cl = rd32(wav + p + 4);
        if (p + 8 + cl > len) cl = (uint32_t)(len - p - 8);   /* tolerate short final chunk */
        if (!memcmp(id, "fmt ", 4)) { fmt = wav + p + 8; fmt_len = cl; }
        else if (!memcmp(id, "data", 4)) { data = wav + p + 8; data_len = cl; }
        else if (!memcmp(id, "smpl", 4)) { smpl = wav + p + 8; smpl_len = cl; }
        p += 8 + cl + (cl & 1);
    }
    if (!fmt || fmt_len < 16 || !data) return -2;

    int afmt = rd16(fmt), nch = rd16(fmt + 2), bits = rd16(fmt + 14);
    long in_rate = (long)rd32(fmt + 4);
    if (afmt == 0xFFFE && fmt_len >= 40) afmt = rd16(fmt + 24);   /* extensible: subformat GUID head */
    if (nch < 1 || nch > 8 || in_rate < 1000 || in_rate > 400000) return -3;
    int bytes_per = bits / 8;
    if (!((afmt == 1 && (bits == 8 || bits == 16 || bits == 24 || bits == 32)) ||
          (afmt == 3 && bits == 32))) return -3;

    long frames = data_len / (long)(bytes_per * nch);
    if (frames < 8) return -4;

    /* decode to float mono */
    float *x = (float *)malloc(sizeof(float) * (size_t)frames);
    if (!x) return -5;
    for (long i = 0; i < frames; i++) {
        double acc = 0;
        for (int c = 0; c < nch; c++) {
            const uint8_t *s = data + (size_t)(i * nch + c) * (size_t)bytes_per;
            double v = 0;
            if (afmt == 3) { float f; memcpy(&f, s, 4); v = f; }
            else if (bits == 8)  v = ((int)s[0] - 128) / 128.0;
            else if (bits == 16) v = (int16_t)rd16(s) / 32768.0;
            else if (bits == 24) {
                int32_t t = s[0] | (s[1] << 8) | (s[2] << 16);
                if (t & 0x800000) t -= 0x1000000;
                v = t / 8388608.0;
            } else { int32_t t = (int32_t)rd32(s); v = t / 2147483648.0; }
            acc += v;
        }
        x[i] = (float)(acc / nch);
    }

    /* pick the highest rate whose 32 KB window fits.
     v0.8: TRUE rates (Orovela S233c, exact at the 2 MHz E clock) and rate 4.
     v0.7's 3140/5831/9420 were 147 cents low (a sharp calibration sine). */
    double dur = (double)frames / (double)in_rate;
    int rate = 1;
    for (int r = 4; r >= 1; r--)
        if (dur <= (double)SAMPLE_BYTES / rate_hz_exact(r)) { rate = r; break; }
    if (force_rate >= 1 && force_rate <= 4) rate = force_rate;
    double out_rate = rate_hz_exact(rate);
    long out_n = (long)floor((double)frames * out_rate / in_rate + 0.5);
    o->truncated = out_n > SAMPLE_BYTES;
    if (out_n > SAMPLE_BYTES) out_n = SAMPLE_BYTES;
    if (out_n < 8) { free(x); return -4; }

    /* windowed-sinc resample (Hann, 16 taps each side) */
    float *y = (float *)malloc(sizeof(float) * (size_t)out_n);
    if (!y) { free(x); return -5; }
    double ratio = (double)in_rate / out_rate;
    double fc = 0.92 * (ratio > 1.0 ? 1.0 / ratio : 1.0);   /* cycles/input-sample, <=0.46 */
    const int TAPS = 16;
    for (long i = 0; i < out_n; i++) {
        double t = i * ratio;
        long k0 = (long)floor(t) - TAPS + 1, k1 = (long)floor(t) + TAPS;
        double acc = 0, wsum = 0;
        for (long k = k0; k <= k1; k++) {
            if (k < 0 || k >= frames) continue;
            double d = t - k;
            double w = 0.5 + 0.5 * cos(M_PI * d / (TAPS + 0.5));      /* Hann over the window */
            double s = (d == 0.0) ? 2.0 * fc * M_PI : sin(2.0 * M_PI * fc * d) / d;
            double c = s * w;
            acc += x[k] * c;
            wsum += c;   /* normalizing by the kernel sum flattens passband ripple */
        }
        y[i] = (float)(acc / (wsum != 0 ? wsum : 1));   /* kernel-sum normalized */
    }
    free(x);

    /* DC-remove + normalize to 95% */
    double mean = 0;
    for (long i = 0; i < out_n; i++) mean += y[i];
    mean /= out_n;
    double peak = 0;
    for (long i = 0; i < out_n; i++) {
        y[i] -= (float)mean;
        double a = fabs(y[i]);
        if (a > peak) peak = a;
    }
    double gain = peak > 1e-9 ? 0.95 / peak : 1.0;

    memset(o->sample, 0x80, SAMPLE_BYTES);
    for (long i = 0; i < out_n; i++) {
        int b = 128 + (int)floor(y[i] * gain * 127.0 + 0.5);
        if (b < 1) b = 1;
        if (b > 255) b = 255;
        o->sample[i] = (uint8_t)b;
    }
    free(y);

    o->rate = rate;
    o->out_n = (int)out_n;
    o->sendpg = (int)((out_n + 511) / 512) - 1;
    if (o->sendpg > 63) o->sendpg = 63;
    if (o->sendpg < 0) o->sendpg = 0;

    /* loop from smpl (positions are input frames -> rescale) */
    if (smpl && smpl_len >= 36 + 24 && rd32(smpl + 28) >= 1) {
        o->unity = (int)rd32(smpl + 12);
        long ls = (long)floor(rd32(smpl + 36 + 8)  * (double)out_rate / in_rate + 0.5);
        long le = (long)floor((rd32(smpl + 36 + 12) + 1.0) * out_rate / in_rate + 0.5) - 1;
        if (le > ls && ls >= 0) {
            o->loop_on = 1;
            o->lstart_pg = (int)((ls + 256) / 512);           /* nearest page */
            o->lend_pg = (int)((le + 1 + 256) / 512) - 1;
            if (o->lstart_pg > 63) o->lstart_pg = 63;
            if (o->lend_pg > o->sendpg) o->lend_pg = o->sendpg;
            if (o->lend_pg < o->lstart_pg) o->lend_pg = o->lstart_pg;
        }
    }
    /* no smpl loop: default the loop REGION to the whole sample so turning
     * looping on later starts from a sensible place (loop = 0..sample end) */
    if (!o->loop_on) {
        o->lstart_pg = 0;
        o->lend_pg = o->sendpg;
    }
    o->endpg = o->loop_on ? o->lend_pg : o->sendpg;

    /* end marker: free-run one-shots only (rates 2-4, no fine start) */
    uint8_t sendsv8[8];
    memset(sendsv8, 0x80, 8);
    uint8_t sendsav = 0x80;
    if (!o->loop_on && rate >= 2) {
        int pos = (o->sendpg < 63) ? (o->sendpg + 1) * 512 : 0x7F00;
        o->sendpos = pos >> 8;
        memcpy(sendsv8, o->sample + pos, 8);
        sendsav = o->sample[pos];
        memset(o->sample + pos, 0x00, 8);
    }

    /* header */
    memset(o->hdr, 0, HDR_BYTES);
    /* v0.8: version-5 header (54 params incl. 76 LFO range and 77 MIDI mod
     * wheel receive) - Orovela 1.3+ loads it; 1.4 is needed for rate 4. */
    o->hdr[0] = 0xC3; o->hdr[1] = 0x3C; o->hdr[2] = HDR_VERSION; o->hdr[3] = 0x01;
    memcpy(o->hdr + 4, PARM_DEFAULTS, NPARM * 4);
    for (int i = 0; i < NPARM; i++) {
        uint8_t *e = o->hdr + 4 + i * 4;
        switch (e[0]) {
        case 1:  e[1] = (uint8_t)rate; break;
        case 7:  if (o->unity >= 0 && o->unity <= 99) e[1] = (uint8_t)o->unity; break;
        case 13: e[1] = (uint8_t)o->loop_on; break;
        case 15: e[1] = 0; break;
        case 16: e[1] = (uint8_t)page_to_param(o->sendpg); break;
        case 17: e[1] = (uint8_t)page_to_param(o->lstart_pg); break;
        case 18: e[1] = (uint8_t)page_to_param(o->lend_pg); break;
        }
    }
    static const uint8_t PRE[5] = {0, 8, 4, 2, 1};
    const int M = 4 + NPARM * 4;           /* metadata block: [220..228] in v5 */
    o->hdr[M + 0] = 3;                     /* SMPSHFT: words are always shift-3 (S53) */
    o->hdr[M + 1] = PRE[rate];             /* SMPPRE: the loader derives the rate from this */
    o->hdr[M + 2] = 0;                     /* SSTART */
    o->hdr[M + 3] = (uint8_t)o->sendpos;   /* SENDPOS */
    o->hdr[M + 4] = sendsav;               /* SENDSAV */
    o->hdr[M + 5] = (uint8_t)o->loop_on;   /* LMODE */
    o->hdr[M + 6] = (uint8_t)o->lstart_pg; /* LSTART */
    o->hdr[M + 7] = (uint8_t)o->sendpg;    /* SENDPG */
    o->hdr[M + 8] = (uint8_t)o->endpg;     /* ENDPG */
    memcpy(o->hdr + M + 9, sendsv8, 8);    /* SENDSV8 */

    snprintf(o->msg, sizeof o->msg,
             "WAV imported: rate %d (%d Hz), %.1f s%s%s%s. Save Disk As%s to keep it.",
             rate, rate_to_hz(rate), out_n / out_rate,
             o->truncated ? " (TRUNCATED to fit)" : "",
             o->loop_on ? ", loop set from smpl chunk (page-quantized)" : ", one-shot",
             (o->unity >= 0) ? ", unity note applied" : "",
             "\x85");
    return 0;
}
