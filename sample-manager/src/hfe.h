/* hfe.h — Mirage HFE container: MFM sector read/write.
 * C port of the proven mirage_hfe.py (byte-exact behavior verified by test_core).
 * Surgical sector edits: only data cells + CRC are re-encoded; gaps, sync and
 * ID fields in the raw bitstream are untouched. */
#ifndef OSM_HFE_H
#define OSM_HFE_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t *d;        /* whole HFE file image (owned) */
    size_t   len;
    int      ntracks;
    int      nsides;
    uint32_t lut_off;  /* byte offset of track LUT */
} HFE;

/* Load/copy/save whole-file image. hfe_from_mem copies the buffer. */
int  hfe_load(HFE *h, const char *path);              /* 0 ok, <0 error */
int  hfe_from_mem(HFE *h, const uint8_t *buf, size_t len);
int  hfe_save(const HFE *h, const char *path);
void hfe_free(HFE *h);

/* Sector I/O. Buffers are caller-owned; *size receives 512 or 1024.
 * Returns 0 ok, <0 on scan/decode failure.
 * crc_ok (may be NULL) receives 1 if the stored data CRC verifies. */
int hfe_read_sector(const HFE *h, int track, int sector,
                    uint8_t *out, int *size, int *crc_ok);
/* payload length must equal the sector's native size (512/1024). */
int hfe_write_sector(HFE *h, int track, int sector,
                     const uint8_t *payload, int len);

uint16_t crc16_ccitt(const uint8_t *data, size_t n, uint16_t crc);

#endif
