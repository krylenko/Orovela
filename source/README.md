# Orovela OS — source

Everything needed to build `DSKA0000_orovela_1.5.hfe` from scratch. The
toolchain is plain Python 3.8+ with no third-party packages (the PDF
generators in `docs/` need `reportlab` and `pypdf`).

## Build

With CMake:

    cmake -S . -B build
    cmake --build build                  # -> build/DSKA0000_orovela_1.5.hfe
    cmake --build build --target verify  # compare with the 1.5 release

Or directly:

    python3 build_unified.py DSKA0000_orovela.hfe
    python3 verify_build.py DSKA0000_orovela.hfe

An unmodified tree reproduces the released image byte for byte (SHA-256
`1af38ccf692552619769675b6de5e955766b5270a3b9119d5e4a1f8a2613d7f6`): 9911
bytes of code at `$9700-$BDB6`, 73 bytes free.

## Files

| File | Purpose |
|---|---|
| `os_unified.asm` | The complete OS: one 6809 assembly source, `ORG $9700` |
| `build_unified.py` | Assembles the source, overlays it on the base disk, generates the frequency and pitch-bend tables, blanks the ten slot headers, and verifies the result by reading it back |
| `assembler_fixed.py` | 6809 assembler written for this project |
| `mirage_hfe.py` | Reads and writes Mirage sectors inside HFE images (MFM, CRCs, ID marks); its output has been verified on real hardware |
| `dis6809.py` | 6809 disassembler, for checking built images |
| `verify_build.py` | Checks a built image against the 1.5 release |
| `DSKA0000_base.hfe` | Base disk: a blank, formatted Mirage disk the build overlays onto. The only data in it is the 17-byte RAM vector stub at the start of track 0 (`$8000-$8010`: IRQ, FIRQ and entry `JMP`s) that the boot ROM needs |
| `new_params.json` | The 54 parameter definitions `{spec, default, min, max}`, the reference for slot headers |
| `docs/` | Parameter-card and manual generators and their text sources, plus the toolchain and disk-format guide |

## How the Mirage boots it

The Mirage's boot ROM, which can't be replaced, loads `$8000-$BDFF` from
tracks 0-10 on every power-up and jumps into the disk-loaded code. Orovela
occupies `$9700-$BDFF`, with its frequency table at `$9600`. The builder
places that window onto these sectors (address, track, sector, size):

    $9600 (1,0) 1024   $9A00 (1,1) 1024   $9E00 (1,2) 1024
    $A200 (1,3) 1024   $A600 (1,4) 1024   $AA00 (1,5) 512
    $AC00 (2,5) 512    $AE00 (3,5) 512    $B000 (4,5) 512
    $B200 (5,5) 512    $B400 (6,5) 512    $B600 (7,5) 512
    $B800 (8,5) 512    $BA00 (9,5) 512    $BC00 (10,5) 512

Tracks 11-70 hold ten program slots (6 tracks each). Disk geometry, the slot
and header format, and the assembler's quirks are documented in
`docs/TOOLCHAIN_AND_DISK_FORMAT.md`.

## Assembler notes

`assembler_fixed.py` emits one flat image starting at the first `ORG` (a
second `ORG` is ignored), has no `RMB`, and always uses extended addressing
(no direct-page optimization). It stops with an error on unknown mnemonics and
out-of-range branches.

## Regenerating the docs

    pip install reportlab pypdf
    cmake --build build --target docs

The text lives in `docs/OROVELA_user_manual.md` and
`../sample-manager/docs/SAMPLE_MANAGER_manual.md`. The parameter card's
content is inside `docs/make_card.py`.
