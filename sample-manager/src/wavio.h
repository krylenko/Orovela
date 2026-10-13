/* wavio.h — WAV import: parse PCM WAVs, resample to a Mirage rate, build a
 * complete Orovela v5 program (32 KB sample + 512-byte header).
 *
 * Rules (mirroring the OS, see claude_TOOLS.md and SYNCP in os_unified.asm):
 * - Rate auto-picked: highest rate whose 32 KB window fits the audio
 *   (4=15504 Hz/2.11 s, 3=10256/3.19, 2=6349/5.16, 1=3419/9.58; true
 *   rates per Orovela S233c); longer input is truncated at rate 1.
 * - Audio is DC-removed, peak-normalized to ~95%, quantized to 8-bit
 *   $80-centered, scrubbed to 1..255, padded with $80.
 * - A smpl chunk in the source WAV sets the loop (page-quantized to the
 *   pager's 512-byte grid, positions rescaled to the target rate) and the
 *   unity note -> param 7. Loop params 13/17/18 and end param 16 are set
 *   with the exact SCALE99 inverse (v = ceil(64*page/41)) so SYNCP
 *   recomputes the same pages on a later edit.
 * - One-shot at rates 2-4 (free-run) gets the 8-zero end marker at the
 *   first 256-aligned position past the audio (SENDPOS set, SENDSV8 =
 *   bytes under it). Rate-1 one-shots and loops are pager-driven: no
 *   marker, SENDPOS=0 (S126/S150 rules).
 */
#ifndef OSM_WAVIO_H
#define OSM_WAVIO_H
#include <stdint.h>
#include <stddef.h>
#include "slots.h"

typedef struct {
    int rate;               /* 1..4 */
    int out_n;              /* real audio samples written (<= 32768) */
    int truncated;
    int loop_on;
    int lstart_pg, lend_pg, sendpg, endpg;
    int sendpos;            /* 0 = none, else high byte of marker offset */
    int unity;              /* -1 = none, else MIDI unity note from smpl */
    uint8_t sample[SAMPLE_BYTES];
    uint8_t hdr[HDR_BYTES];
    char msg[200];          /* human summary for the status line */
} WavImport;

/* 0 ok; -1 not RIFF/WAVE; -2 no fmt/data; -3 unsupported encoding;
 * -4 empty audio; -5 malformed chunk structure.
 * force_rate: 0 = auto-pick by length, 1..4 = force that rate (audio that
 * does not fit the forced rate's window is truncated). */
int wav_import_build_rate(const uint8_t *wav, size_t len, int force_rate, WavImport *out);
int wav_import_build(const uint8_t *wav, size_t len, WavImport *out);

#endif
