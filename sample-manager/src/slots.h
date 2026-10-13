/* slots.h — Orovela slot format, .oro program files, WAV export, disk checks.
 * Format authority: claude_TOOLS.md §2/§4/§5 (Orovela 1.0).
 *
 * Slot s (0-9) = 6 tracks from 11+6s. Sample = 34 sectors (SMTAB order) =
 * 32768 bytes exactly. Header at (base+4, sector 5): magic $C3 $3C, version,
 * flags bit0 = has-sample, PARMTAB image of N x 4 bytes at [4..], then 9 metadata
 * bytes + SENDSV8. N by version: v3 = 52 (sample manager <= 0.7), v4 = 53
 * (Orovela 1.2, +param 76), v5 = 54 (Orovela 1.3+, +param 77). v0.8 reads all
 * three and writes v5.
 *
 * .oro file format (defined here, v1):
 *   [0..3]     "ORO1"
 *   [4..515]   the slot's 512-byte header sector image, byte-exact
 *   [516..33283] the slot's 32768 sample bytes, byte-exact
 *   total 33284 bytes. Byte-exact round trip disk->oro->disk is guaranteed
 *   (sample data is copied verbatim; it may legitimately contain the 8-zero
 *   end marker, so NO scrubbing is applied on .oro import).
 */
#ifndef OSM_SLOTS_H
#define OSM_SLOTS_H
#include "hfe.h"

#define SLOT_COUNT      10
#define SAMPLE_BYTES    32768
#define HDR_BYTES       512
#define ORO_MAGIC       "ORO1"
#define ORO_FILE_BYTES  (4 + HDR_BYTES + SAMPLE_BYTES)
#define NPARM           54      /* entries written (v5) */
#define HDR_VERSION     5

enum slot_kind {
    SLOT_EMPTY = 0,     /* all-zero magic */
    SLOT_V3,            /* $C3 $3C version 3, 4 or 5 — an Orovela program
                           (name kept from v0.7; v0.8 accepts all three) */
    SLOT_OLDVER,        /* $C3 $3C, any other version — incompatible generation */
    SLOT_ANCIENT,       /* $A5 $5A — pre-unified patch slot */
    SLOT_INVALID,       /* anything else */
    SLOT_UNREADABLE     /* sector read failed */
};

typedef struct {
    enum slot_kind kind;
    int has_sample;     /* flags bit0 (V3 only) */
    int version;        /* 3, 4 or 5 (V3 kind only) */
    int meta;           /* offset of the metadata block (SMPSHFT) in the header */
    int rate;           /* 1..4 (from SMPPRE, as the OS loader derives it) */
    int rate_hz;        /* 3419 / 6349 / 10256 / 15504 (rounded), 0 if unknown */
    int loop_on;        /* LMODE != 0 (V3 only) */
    uint8_t header[HDR_BYTES];
} SlotInfo;

int slot_base_track(int s);                      /* 11 + 6*s */
int slot_info(const HFE *h, int s, SlotInfo *si);/* 0 ok (kind always set) */
int slot_read_sample(const HFE *h, int s, uint8_t *buf32k);
int slot_write_sample(HFE *h, int s, const uint8_t *buf32k);
int slot_write_header(HFE *h, int s, const uint8_t *hdr512);
int slot_clear(HFE *h, int s);                   /* zero the header sector */

/* The "cursed sector" (RESOLVED at S213/unified147): OS builds <= unified146
 * never wrote sample sector index 32 (rel-track 5, sector 3 = DOC $7800-
 * $7BFF) and their loader concealed the gap by copying the PRECEDING 1 KB
 * over it with a $00 -> $01 scrub. unified147 writes and reads all 34
 * sectors. A legacy slot is fingerprinted by an ALL-ZERO idx32 region
 * (captured audio can never be $00): rendering conceals it exactly as the
 * old loader did, and .oro import bakes the concealment into the disk so
 * legacy sounds play under 147 exactly as they did under <= 146. Slots with
 * real data there are rendered verbatim. Byte-exact export (.oro) never
 * transforms. */
#define CURSED_OFF  30720   /* DOC $7800 */
#define CURSED_LEN  1024

/* 1 if the idx32 region is all zeros (pre-147 save / blank), else 0. */
int cursed_region_blank(const uint8_t *sample32k);

/* The sample as the OS's loader leaves it in DOC RAM: legacy all-zero idx32
 * region concealed from its neighbour (147+ slots pass through verbatim),
 * every $00 scrubbed to $01. Use for WAV export and audition. Use
 * slot_read_sample for byte-exact copies. */
int slot_read_audio_playback(const HFE *h, int s, uint8_t *buf32k);

/* PARMTAB access within a 512-byte header image: value for a spec, -1 if absent */
int hdr_param_by_spec(const uint8_t *hdr512, int spec);
int hdr_nparm(const uint8_t *hdr512);     /* 52/53/54 by version, 0 if not a program */
int hdr_meta_off(const uint8_t *hdr512);  /* 4 + 4*nparm */
int rate_to_hz(int rate);                 /* rounded Hz (WAV headers, display) */
double rate_hz_exact(int rate);           /* 2 MHz / 585, 315, 195, 129 */
int smppre_to_rate(int smppre);           /* 8/4/2/1 -> 1/2/3/4, 0 otherwise */

/* .oro in-memory build/parse. buf is ORO_FILE_BYTES. */
void oro_build(uint8_t *buf, const uint8_t *hdr512, const uint8_t *sample32k);
int  oro_parse(const uint8_t *buf, size_t len,
               const uint8_t **hdr512, const uint8_t **sample32k); /* 0 ok */

/* Slot <-> .oro file */
int slot_export_oro(const HFE *h, int s, const char *path);
int slot_import_oro(HFE *h, int s, const char *path);

/* WAV export: 16-bit signed mono PCM at the slot's capture rate. */
int slot_export_wav(const HFE *h, int s, const char *path);

/* Orovela disk validation:
 * 0 = OK; -1 = not readable as a Mirage HFE (bad container/sectors/CRC);
 * -2 = readable but not an Orovela disk (frequency-table fingerprint at
 *      track 1 sector 0 fails: 128 16-bit LE words, monotone non-decreasing
 *      over the playable range with octave ratios ~2.0). */
int disk_validate_orovela(const HFE *h);

/* Blank all ten slot header sectors (used by New Disk). */
int disk_blank_slots(HFE *h);

#endif
