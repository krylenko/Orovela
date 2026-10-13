/* test_fix.c — cursed-sector regression suite across OS generations.
 *   viz_disk.hfe   = legacy (<=146) save: idx32 all zeros -> conceal on render,
 *                    bake on import.
 *   return146.hfe  = cursediag146 save: idx32 holds real audio -> verbatim
 *                    render, verbatim import.
 */
#include "../src/hfe.h"
#include "../src/slots.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails = 0;
#define CHECK(cond, name) do { \
    if (cond) printf("PASS  %s\n", name); \
    else { printf("FAIL  %s\n", name); fails++; } \
} while (0)

static int scrub_eq(const uint8_t *play, const uint8_t *raw, int lo, int hi)
{
    for (int i = lo; i < hi; i++) {
        uint8_t v = raw[i] ? raw[i] : 1;
        if (play[i] != v) return 0;
    }
    return 1;
}

int main(void)
{
    /* ---------- legacy disk ---------- */
    HFE h;
    if (hfe_load(&h, "viz_disk.hfe") != 0) { printf("SKIP: viz_disk.hfe missing\n"); return 1; }
    uint8_t *raw = malloc(SAMPLE_BYTES), *play = malloc(SAMPLE_BYTES), *tmp = malloc(SAMPLE_BYTES);

    slot_read_sample(&h, 0, raw);
    CHECK(cursed_region_blank(raw), "legacy: idx32 fingerprint = blank");
    slot_read_audio_playback(&h, 0, play);
    int conc = 1;
    for (int i = 0; i < CURSED_LEN; i++) {
        uint8_t src = raw[CURSED_OFF - CURSED_LEN + i];
        if (play[CURSED_OFF + i] != (src ? src : 1)) conc = 0;
    }
    CHECK(conc, "legacy: render conceals from preceding 1 KB");
    CHECK(scrub_eq(play, raw, 0, CURSED_OFF) &&
          scrub_eq(play, raw, CURSED_OFF + CURSED_LEN, SAMPLE_BYTES),
          "legacy: rest identical modulo scrub");
    CHECK(slot_export_oro(&h, 0, "legacy.oro") == 0, "legacy: .oro export (raw, zeros intact)");
    hfe_free(&h);

    /* ---------- 146/147-style disk: real data in idx32 ---------- */
    if (hfe_load(&h, "return146.hfe") != 0) { printf("SKIP: return146.hfe missing\n"); return 1; }
    for (int s = 0; s <= 7; s += 7) {
        char name[64];
        slot_read_sample(&h, s, raw);
        sprintf(name, "slot %d: idx32 fingerprint = data present", s);
        CHECK(!cursed_region_blank(raw), name);
        slot_read_audio_playback(&h, s, play);
        sprintf(name, "slot %d: render is verbatim modulo scrub (NO conceal)", s);
        CHECK(scrub_eq(play, raw, 0, SAMPLE_BYTES), name);
    }
    CHECK(slot_export_oro(&h, 0, "modern.oro") == 0, "modern: .oro export");
    CHECK(slot_export_wav(&h, 0, "return146_slot0.wav") == 0, "modern: WAV export");
    hfe_free(&h);

    /* ---------- import behavior on a fresh 147 disk ---------- */
    extern const unsigned char BASE_DISK[];
    extern const unsigned int  BASE_DISK_LEN;
    HFE nd;
    CHECK(hfe_from_mem(&nd, BASE_DISK, BASE_DISK_LEN) == 0, "embedded 147 base loads");
    CHECK(disk_validate_orovela(&nd) == 0, "embedded 147 base validates as Orovela");

    /* legacy .oro -> concealment BAKED into the disk */
    CHECK(slot_import_oro(&nd, 2, "legacy.oro") == 0, "import legacy.oro into slot 2");
    slot_read_sample(&nd, 2, tmp);
    CHECK(!cursed_region_blank(tmp), "legacy import: idx32 no longer blank (baked)");
    size_t ln; FILE *f = fopen("legacy.oro", "rb");
    fseek(f, 0, SEEK_END); ln = ftell(f); fseek(f, 4 + HDR_BYTES, SEEK_SET);
    uint8_t *lsmp = malloc(SAMPLE_BYTES);
    if (fread(lsmp, 1, SAMPLE_BYTES, f) != SAMPLE_BYTES) { printf("FAIL read legacy.oro\n"); return 1; }
    fclose(f); (void)ln;
    int baked = 1;
    for (int i = 0; i < CURSED_LEN; i++) {
        uint8_t v = lsmp[CURSED_OFF - CURSED_LEN + i];
        if (tmp[CURSED_OFF + i] != (v ? v : 1)) baked = 0;
    }
    for (int i = 0; i < CURSED_OFF; i++) if (tmp[i] != lsmp[i]) { baked = 0; break; }
    CHECK(baked, "legacy import: baked bytes = scrubbed copy of preceding 1 KB, rest verbatim");

    /* modern .oro -> byte-exact verbatim */
    CHECK(slot_import_oro(&nd, 3, "modern.oro") == 0, "import modern.oro into slot 3");
    CHECK(slot_export_oro(&nd, 3, "modern_back.oro") == 0, "re-export slot 3");
    FILE *fa = fopen("modern.oro", "rb"); FILE *fb = fopen("modern_back.oro", "rb");
    uint8_t *ba = malloc(ORO_FILE_BYTES), *bb = malloc(ORO_FILE_BYTES);
    size_t na = fread(ba, 1, ORO_FILE_BYTES, fa), nb = fread(bb, 1, ORO_FILE_BYTES, fb);
    fclose(fa); fclose(fb);
    CHECK(na == ORO_FILE_BYTES && nb == ORO_FILE_BYTES && memcmp(ba, bb, ORO_FILE_BYTES) == 0,
          "modern .oro round trip byte-exact (no bake)");
    hfe_free(&nd);

    printf(fails ? "\n%d FAILURES\n" : "\nALL FIX TESTS PASSED\n", fails);
    return fails ? 1 : 0;
}
