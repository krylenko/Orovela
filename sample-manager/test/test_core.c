/* test_core.c — Linux harness proving the C core is byte-exact against the
 * Python reference toolchain. Run from ~/osm. */
#include "../src/hfe.h"
#include "../src/slots.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int fails = 0;
#define CHECK(cond, name) do { \
    if (cond) printf("PASS  %s\n", name); \
    else { printf("FAIL  %s\n", name); fails++; } \
} while (0)

static uint8_t *slurp(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f) { *n = 0; return NULL; }
    fseek(f, 0, SEEK_END); long ln = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *b = malloc((size_t)ln);
    if (fread(b, 1, (size_t)ln, f) != (size_t)ln) { free(b); fclose(f); *n = 0; return NULL; }
    fclose(f); *n = (size_t)ln; return b;
}

static int linear_dump(const HFE *h, uint8_t *out)  /* 450560 bytes */
{
    int off = 0;
    for (int t = 0; t < 80; t++)
        for (int s = 0; s < 6; s++) {
            int size = 0, crc = 0;
            if (hfe_read_sector(h, t, s, out + off, &size, &crc) != 0) return -1;
            if (!crc) return -2;
            off += size;
        }
    return off;
}

int main(void)
{
    /* 1+2: byte-exact linear read + CRC across every sector of both images */
    const char *imgs[2] = {"DSKA0000_slot_d2.hfe", "DSKA0000_orovela_1.0.hfe"};
    const char *refs[2] = {"DSKA0000_slot_d2.linear.bin", "DSKA0000_orovela_1.0.linear.bin"};
    for (int i = 0; i < 2; i++) {
        HFE h;
        CHECK(hfe_load(&h, imgs[i]) == 0, "load HFE");
        uint8_t *lin = malloc(450560);
        int n = linear_dump(&h, lin);
        CHECK(n == 450560, "all 480 sectors read, sizes+CRC OK");
        size_t rn; uint8_t *ref = slurp(refs[i], &rn);
        CHECK(ref && rn == 450560 && memcmp(lin, ref, rn) == 0,
              "byte-exact vs Python reference");
        free(lin); free(ref); hfe_free(&h);
    }

    /* 3: sector write round trip (1024B and 512B sectors) */
    {
        HFE h;
        hfe_load(&h, "DSKA0000_orovela_1.0.hfe");
        uint8_t p1[1024], p2[512], p3[1024], rb[1024];
        for (int i = 0; i < 1024; i++) p1[i] = (uint8_t)(i * 7 + 3);
        for (int i = 0; i < 512; i++)  p2[i] = (uint8_t)(0xA5 ^ i);
        for (int i = 0; i < 1024; i++) p3[i] = (uint8_t)(255 - (i & 0xFF));
        CHECK(hfe_write_sector(&h, 11, 0, p1, 1024) == 0, "write (11,0) 1024B");
        CHECK(hfe_write_sector(&h, 11, 5, p2, 512) == 0,  "write (11,5) 512B");
        CHECK(hfe_write_sector(&h, 70, 3, p3, 1024) == 0, "write (70,3) 1024B");
        int size, crc;
        hfe_read_sector(&h, 11, 0, rb, &size, &crc);
        CHECK(size == 1024 && crc && memcmp(rb, p1, 1024) == 0, "re-read (11,0) matches, CRC OK");
        hfe_read_sector(&h, 11, 5, rb, &size, &crc);
        CHECK(size == 512 && crc && memcmp(rb, p2, 512) == 0, "re-read (11,5) matches, CRC OK");
        hfe_read_sector(&h, 70, 3, rb, &size, &crc);
        CHECK(size == 1024 && crc && memcmp(rb, p3, 1024) == 0, "re-read (70,3) matches, CRC OK");
        CHECK(hfe_save(&h, "test_written.hfe") == 0, "save test_written.hfe");
        hfe_free(&h);
    }

    /* 4: Orovela validation — positive and negative */
    {
        HFE h;
        hfe_load(&h, "DSKA0000_orovela_1.0.hfe");
        CHECK(disk_validate_orovela(&h) == 0, "1.0 image validates as Orovela");
        /* corrupt the freq table with code-like bytes -> must be rejected */
        uint8_t fake[1024];
        for (int i = 0; i < 1024; i++) fake[i] = (uint8_t)(0xB6 + (i * 37));
        hfe_write_sector(&h, 1, 0, fake, 1024);
        CHECK(disk_validate_orovela(&h) == -2, "code-like track (1,0) rejected (not Orovela)");
        hfe_free(&h);

        HFE d2;
        hfe_load(&d2, "DSKA0000_slot_d2.hfe");
        printf("info  slot_d2 validate result: %d\n", disk_validate_orovela(&d2));
        hfe_free(&d2);
    }

    /* 5: slot classification of the built 1.0 image (stale v2 slots expected) */
    {
        HFE h;
        hfe_load(&h, "DSKA0000_orovela_1.0.hfe");
        static const enum slot_kind expect[10] = {
            SLOT_EMPTY, SLOT_OLDVER, SLOT_EMPTY, SLOT_EMPTY, SLOT_OLDVER,
            SLOT_OLDVER, SLOT_EMPTY, SLOT_EMPTY, SLOT_EMPTY, SLOT_OLDVER };
        int ok = 1;
        for (int s = 0; s < 10; s++) {
            SlotInfo si; slot_info(&h, s, &si);
            if (si.kind != expect[s]) ok = 0;
        }
        CHECK(ok, "slot classification (empty vs stale-v2) matches Python");
        CHECK(disk_blank_slots(&h) == 0, "blank all slot headers");
        int allempty = 1;
        for (int s = 0; s < 10; s++) {
            SlotInfo si; slot_info(&h, s, &si);
            if (si.kind != SLOT_EMPTY) allempty = 0;
        }
        CHECK(allempty, "all slots EMPTY after blanking (New Disk state)");
        hfe_free(&h);
    }

    /* 6: synthetic program -> import -> export byte-exact round trip */
    {
        uint8_t hdr[HDR_BYTES]; memset(hdr, 0, sizeof hdr);
        hdr[0] = 0xC3; hdr[1] = 0x3C; hdr[2] = 0x03; hdr[3] = 0x01;
        for (int i = 0; i < NPARM; i++) {          /* plausible PARMTAB */
            hdr[4 + i * 4 + 0] = (uint8_t)(i + 1); /* spec */
            hdr[4 + i * 4 + 1] = (uint8_t)(i * 2); /* value */
            hdr[4 + i * 4 + 2] = 0;
            hdr[4 + i * 4 + 3] = 99;
        }
        hdr[4 + 0 * 4 + 1] = 3;   /* spec 1 = rate 3 */
        hdr[217] = 1;             /* LMODE on */
        uint8_t sample[SAMPLE_BYTES];
        for (int i = 0; i < SAMPLE_BYTES; i++) {
            double v = 128.0 + 100.0 * sin(2.0 * M_PI * 220.0 * i / 9420.0);
            int b = (int)(v + 0.5);
            if (b < 1) b = 1; if (b > 255) b = 255;
            sample[i] = (uint8_t)b;
        }
        memset(sample + SAMPLE_BYTES - 8, 0, 8);   /* deliberate 8-zero end marker */
        uint8_t oro[ORO_FILE_BYTES];
        oro_build(oro, hdr, sample);
        FILE *f = fopen("test_prog.oro", "wb");
        fwrite(oro, 1, sizeof oro, f); fclose(f);

        HFE h;
        hfe_load(&h, "DSKA0000_orovela_1.0.hfe");
        disk_blank_slots(&h);
        CHECK(slot_import_oro(&h, 3, "test_prog.oro") == 0, "import .oro into slot 3");
        SlotInfo si; slot_info(&h, 3, &si);
        CHECK(si.kind == SLOT_V3 && si.has_sample && si.rate == 3
              && si.rate_hz == 9420 && si.loop_on, "slot 3 parses as V3/rate3/loop");
        CHECK(slot_export_oro(&h, 3, "test_prog_back.oro") == 0, "export slot 3 -> .oro");
        size_t bn; uint8_t *back = slurp("test_prog_back.oro", &bn);
        CHECK(back && bn == ORO_FILE_BYTES && memcmp(back, oro, bn) == 0,
              "disk->oro->disk byte-exact (8-zero marker preserved, no scrub)");
        free(back);
        CHECK(slot_export_wav(&h, 3, "test_prog.wav") == 0, "export slot 3 -> WAV");
        CHECK(hfe_save(&h, "test_slot3.hfe") == 0, "save test_slot3.hfe for Python cross-check");
        /* refuse invalid .oro */
        f = fopen("test_bad.oro", "wb");
        fwrite(oro, 1, 1000, f); fclose(f);
        CHECK(slot_import_oro(&h, 4, "test_bad.oro") < 0, "truncated .oro rejected");
        hfe_free(&h);
    }

    printf(fails ? "\n%d FAILURES\n" : "\nALL TESTS PASSED\n", fails);
    return fails ? 1 : 0;
}
