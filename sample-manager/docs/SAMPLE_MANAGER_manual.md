<!--
OROVELA SAMPLE MANAGER USER MANUAL — TEXT SOURCE. Edit this file, then run:
    python3 make_manual.py SAMPLE_MANAGER_manual.md
(writes SAMPLE_MANAGER_manual.pdf). Same format as OROVELA_user_manual.md, plus:
  title: / theme:         header subtitle; colour theme (green | lavender)
  # WINDOW <title>        schematic of the program window, spanning `span:` grid slots
    span: 3               how many of the 4 slots it covers
    top: A | B | C        buttons along the top
    toplabel: TEXT        lavender tag after the top buttons
    columns: A | B ...    slot-list column headings
    row: a | b | ...      one slot-list row (repeat)
    selected: N           highlight row N (0 = first)
    bottom: A | B ...     buttons under the list
    bottomlabel: TEXT     lavender tag after the bottom buttons
    status: text          status line
  Indented "- " lines are sub-bullets; "# COLUMN" forces a column break (text also
  flows into the next column on its own when one fills).
-->
version: Sample Manager 1.0 · 2026-10-13
title: Sample Manager — User Manual
theme: lavender
footer: Orovela on the instrument: see the Orovela User Manual and Parameter Reference card.

# WINDOW Orovela Sample Manager 1.0
span: 3
top: Open Disk... | New Disk | Save Disk As...
toplabel: WHOLE DISK
columns: Slot | Contents | Rate | Loop | Length
row: 0 | Program + sample | 3  (10256 Hz) | On | 3.2 s
row: 1 | Program + sample | 4  (15504 Hz) | Off | 2.1 s
row: 2 | Empty | — | — | —
row: 3 | Empty | — | — | —
row: 4 | Empty | — | — | —
selected: 1
bottom: Play | Extract WAV... | Export .oro... | Import .oro... | Import WAV... | Clear Slot
bottomlabel: SELECTED SLOT
status: Disk loaded. Select a slot to extract, export, import or play.

# NOTE QUICK START
**1** New Disk (or Open Disk...)
**2** Click a slot row
**3** Import WAV... and pick a file
**4** Save Disk As..., then flash the .hfe to your Gotek / HxC
**5** On the Mirage: SEQ LOAD, slot digit, ENTER

# COLUMN
## WHAT IT IS
A Windows program for the ten program slots on an Orovela disk image (**.hfe**). No install
and no dependencies - just run **OrovelaSampleManager-1.0.exe**.

Use it to turn any WAV into a playable Orovela program, pull samples out as WAVs, back up
programs, and move them between disks. It works on disk image files only; flash the result
to your floppy emulator as usual.

A **program** is the 32 KB sample plus all 54 parameters - exactly what SEQ SAVE stores on
the Mirage.

## THE DISK
- **Open Disk...** loads an Orovela .hfe. It checks the sector structure and CRCs and refuses stock-OS or other non-Orovela disks.
- **New Disk** creates a fresh disk carrying **Orovela 1.5**, all ten slots empty.
- **Save Disk As...** writes the image (default name DSKA0000_custom.hfe). Nothing reaches a file until you do this; the program warns before discarding unsaved changes.

# COLUMN
## SLOT ACTIONS
Click a row first; the buttons under the list act on that slot.
- **Play** auditions the sample through your PC (the full 32 KB at its capture rate). Click again to stop.
- **Extract WAV...** saves a 16-bit mono WAV at the true capture rate. Looped programs carry a standard loop (smpl) chunk and the base note, so DAWs and samplers see the loop.
- **Export .oro...** saves the whole program - sample, parameters and capture data - as one byte-exact file.
- **Import .oro...** writes a program file into the slot.
- **Import WAV...** builds a program from any WAV (next column).
- **Clear Slot** empties the slot.

Imports ask before overwriting a slot that isn't empty; Clear Slot always asks.

> Slots listed as **Old format** or **Ancient patch slot** come from early Orovela builds. They can be cleared or overwritten, not exported.

# COLUMN
## IMPORTING A WAV
1. Select a slot, click **Import WAV...** and pick the file. Any PCM 8/16/24/32-bit or 32-bit float WAV, mono or stereo, at any sample rate.
2. Choose the rate. **Yes** = automatic: the highest rate whose window holds the whole file. **No** = offered rate 4, then 3, 2, 1 in turn. Audio past the end of the window is cut off.
3. The audio is resampled, DC-removed, normalized to 95% peak and converted to 8-bit.
4. **Save Disk As...**, flash, and load the slot on the Mirage.

- **Rate 4**: 15504 Hz, 2.1 s
- **Rate 3**: 10256 Hz, 3.2 s
- **Rate 2**: 6349 Hz, 5.2 s
- **Rate 1**: 3419 Hz, 9.6 s

### Loops and pitch
A loop in the WAV (smpl chunk) becomes the program's loop, snapped to 512-sample steps; the
WAV's unity note becomes the base note (param 7). With no loop, the program is a one-shot
that stops exactly where the audio ends.

> Round trip: Extract WAV, set loop points in your editor, Import WAV - the loop comes back.

# COLUMN
## BACKUPS + MOVING PROGRAMS
> Flashing a new Orovela version onto a disk blanks all ten slots. **Export .oro backups first.**

1. **Open Disk...** the image you've been saving to on the Mirage.
2. **Export .oro...** each program you want to keep.
3. **New Disk** (or open another disk) and **Import .oro...** them into slots.
4. **Save Disk As...** and flash.

.oro files move freely between Orovela 1.3, 1.4 and 1.5 and Sample Manager 0.8 and 1.0.

## NOTES
- Imported WAVs need Orovela 1.3 or later on the instrument (rate 4 needs 1.4). Disks made with New Disk already carry 1.5.
- WAVs extracted with Sample Manager 0.7 or earlier are tagged about 1.5 semitones flat - extract them again with 1.0.
- Extract WAV always exports the full 32 KB, so one-shots include the silent tail.
- File and folder names with non-Western characters may not open.
