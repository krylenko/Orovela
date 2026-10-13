# Orovela Sample Manager v1.0

A self-contained Windows tool for managing sample programs on Orovela disk
images (Ensoniq Mirage DSK-8 running the Orovela OS). No installation, no
Python, no dependencies — just run `OrovelaSampleManager-1.0.exe`.

## What's new in v1.0 (for Orovela 1.5; was briefly v0.8.1)

- **New Disk embeds Orovela 1.5** (boot on param 21, saw in tune, sample/loop
  trim fixes, end marker survives loop toggles). Nothing else changed: the slot
  format is identical (header v5), and .oro / WAV files move freely between
  v0.8 and v1.0 and between Orovela 1.3, 1.4 and 1.5.

## What's new in v0.8 (for Orovela 1.4)

- **Correct capture rates.** Every rate is now its true value, exact at the
  Mirage's 2 MHz clock: **rate 1 = 3419 Hz, 2 = 6349 Hz, 3 = 10256 Hz,
  4 = 15504 Hz**. v0.7's 3140 / 5831 / 9420 came from a calibration tone that
  was ~147 cents sharp, so v0.7 tagged every extracted WAV ~1.5 semitones flat
  and resampled every imported WAV to the wrong target. Re-extract anything you
  exported with v0.7; WAVs imported with v0.7 play ~147 cents sharp at
  param 6 = 50 (re-import them with v0.8, or retune by ear).
- **Rate 4** (Orovela 1.4): extract, play, and import at 15504 Hz (2.1 s).
  Auto-pick now chooses among four rates; the manual override offers rate 4.
- **Reads slots saved by the OS since 1.2.** v0.7 showed Orovela 1.2 (header
  v4) and 1.3+ (v5) saves as "old format"; v0.8 reads versions 3, 4 and 5 and
  exports/imports all of them as .oro.
- **Writes version-5 headers** (54 params incl. 76 LFO range and 77 MIDI mod
  wheel receive, both default 0). Imported WAVs need Orovela 1.3 or later;
  rate-4 imports need 1.4.
- **New Disk embeds Orovela 1.4.**

## What it does

- **Open Disk…** — load an Orovela `.hfe` disk image. The tool verifies the
  disk structurally (sector layout + CRCs) and fingerprints the Orovela
  frequency table; stock-OS and other non-Orovela disks are refused.
- **New Disk** — create a fresh disk in memory from the embedded Orovela OS
  (1.5 since v1.0) with all 10 slots empty.
- **Save Disk As…** — write the current disk to a `.hfe` file, ready to flash.
- Per slot (select a row first):
  - **Play** — audition the slot's sample through your PC audio
    (full 32 KB buffer at its capture rate). Click again to stop.
  - **Extract WAV…** — export the sample as 16-bit mono WAV at the true
    capture rate (3419 / 6349 / 10256 / 15504 Hz), lossless from the 8-bit data.
    Looped programs get a standard `smpl` chunk (loop points + unity note
    from param 7), so editors and samplers see the loop.
  - **Export .oro…** — save the complete program (all parameters, capture
    metadata, and the sample) as a single `.oro` file.
  - **Import .oro…** — write a program into the selected slot of the current
    disk. Works on opened disks and new disks alike, so copying slots
    between disks is just export → import.
  - **Import WAV…** — turn any WAV (PCM 8/16/24/32-bit or 32-bit float,
    mono or stereo, any rate) into an Orovela program in the selected slot:
    resampled (windowed-sinc) to the highest Mirage rate that fits the
    length (2.1 / 3.2 / 5.2 / 9.6 s; longer input is truncated at rate 1),
    DC-removed, peak-normalized, 8-bit converted and scrubbed. A `smpl`
    loop in the WAV sets the program's loop (quantized to the pager's
    512-byte pages) and its unity note sets the base note (param 7);
    one-shots get a proper end marker so they stop exactly at the audio's
    end on hardware, and their loop region defaults to the whole sample so
    turning looping on later starts from a sensible place (v0.6). The rate
    is picked automatically from the length, with a manual override prompt
    if you want a lower rate (v0.6). Export .oro afterwards to keep it as a
    program file — extract → edit in your DAW → re-import round-trips loop
    points.
  - **Clear Slot** — blank the slot header (the OS then treats it as empty).

Typical workflow: open the disk you've been saving to on hardware, export
your keepers as `.oro` files, then New Disk → import up to 10 of them →
Save Disk As. Because every OS re-flash blanks tracks 11–79, exporting
`.oro` backups before flashing a new OS build is the way to carry sounds
across updates.

## The .oro format (v1)

Byte-exact container for one Orovela program (33,284 bytes):

    [0..3]        "ORO1" magic
    [4..515]      the slot's 512-byte header sector, verbatim
                  (magic $C3 $3C, version 3/4/5, flags, 52/53/54 x 4 PARMTAB image,
                  capture metadata, SENDSV8)
    [516..33283]  the 32,768 sample bytes, verbatim

Disk → .oro → disk round trips are byte-identical. Sample data is copied
without modification (it may legitimately contain the 8-zero end marker, so
no zero-scrubbing is applied).

## The cursed sector, resolved (v0.3-v0.4)

History: OS builds through unified146 never wrote sample sector index 32
(pages 60–61 of the buffer) and concealed the gap at load by repeating the
preceding 1 KB — the exit seam of that repeat was the click audible after
every save/load round trip. The S213 diagnostic proved the "cursed sector"
write actually lands cleanly, so **unified148** (the OS this version embeds
for New Disk) writes and reads all 34 sectors: full 32 KB, byte-true round
trips, no concealment, no click.

The tool is now content-aware across both generations:

- A slot whose pages 60–61 are all zeros is a legacy (≤146) save: WAV/Play
  reproduce the old loader's concealment — exactly what the OS that saved
  it played — and importing such a `.oro` onto a disk **bakes the
  concealment in**, so legacy sounds play under unified147+ exactly as they
  did before.
- A slot with real data there (saved by unified146+) renders and imports
  verbatim.
- `.oro` export is always a byte-exact raw copy.

## Notes and limits

- Slots shown as **Old format (incompatible)** or **Ancient patch slot** are from
  earlier OS generations; they can't be exported, only cleared or overwritten.
- The embedded OS is **Orovela 1.5** (v1.0; v0.8 embedded 1.4). .oro files from every version (header
  v3, v4, v5) import; the OS loads all three.
- WAV extraction exports the full 32 KB buffer; for one-shot samples the tail
  past the end marker is included.
- File paths with non-Western characters may not resolve (ANSI file dialogs).
- Mirage loops are page-quantized (512 samples); imported loop points snap
  to the nearest page.

## Verification (v1.0)

Embedded base regenerated from DSKA0000_orovela_1.5.hfe: OS sectors (track 0 +
the code window) byte-identical to the 1.5 release, all 10 slot headers blank.
The full v0.8 suite passes unchanged (import/write/reload/export at rates 3-4,
v5 headers), and a disk written by it carries the 1.5 OS. Under Wine, New Disk
reports "Orovela 1.5, all 10 slots empty".

## Verification (v0.8)

Tested on Linux against real Orovela data (test/test_v08.c, 30 checks + a v3-parse check):
OS-saved v5 slots from the rate-4 calibration disks parse with the right
version, metadata offset, rate and Hz; a synthesized v3 (v0.7-style) slot still
parses; WAV auto-rate picks 4/3/2/1 by length; a 261.63 Hz sine imported at
rate 4 stores exactly 59.259 bytes per cycle (= 15503.88 / 261.63); the
imported header's 54-entry parameter layout matches an OS-saved header entry
for entry; the result written into the embedded 1.4 base reads back through
the independent Python codec and through an emulation of the 1.4 loader
(version gate, 216-byte block, SMPPRE 1 -> rate 4); disk -> .oro -> disk is
byte-identical for a v5 slot; looped WAV export carries the right smpl points
and sample period. The exe was run under Wine: New Disk reports Orovela 1.4
with 10 empty slots, and opening a hardware-returned disk lists the rate-4
slots as "4 (15504 Hz), 2.1 s".

## Verification (earlier versions)

The MFM sector codec is a C port of `mirage_hfe.py` — the toolkit that has
been writing hardware-verified Orovela disks all along. This build passed:
all 960 sectors of two reference images read byte-exact against the Python
reference; Python re-reads C-written sectors byte-exact with neighbouring
sectors untouched; disk→.oro→disk round trip byte-identical; and the exe
itself (run under Wine, driven through its real file dialogs) produced a new
disk whose OS tracks are byte-identical to the verified 1.0 build with the
imported program placed correctly. The v0.2 cursed-sector fix was verified
against a real hardware-saved disk: the concealed region matches SMLOAD2's
semantics exactly (repeat of the preceding 1 KB, no $00 anywhere in the
rendered audio) and the GUI's extraction is byte-identical to the tested
core. Source and tests are in this folder; see BUILD.md. The v0.4 embedded base (unified148) adds the end-marker re-place, the header version gate, and builder-blanked slots — all byte-verified against hardware-returned disks.
