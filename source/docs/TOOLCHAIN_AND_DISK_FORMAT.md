> This is the project's working reference for the toolchain and the Orovela disk
> format, kept as written during development. It mentions some analysis scripts,
> session logs and findings documents that are not part of this repository.

# OROVELA TOOLCHAIN + DISK FORMAT GUIDE
For building the OS and for writing helper utilities (disk-image managers,
slot tools, sample import/export). Everything here runs on the workstation in
python3 — no flash cycle needed except for OS changes themselves.

--------------------------------------------------------------------------------
## 1. THE FILES

    assembler_fixed.py   Assembler6809. a=Assembler6809(); code=a.assemble(src);
                         symbols in a.symbols (fallback a.labels).
                         QUIRKS: emits ONE flat image from the FIRST ORG (a
                         second ORG is silently dropped — inject out-of-span
                         bytes into the HFE post-build); no RMB; all-extended
                         addressing (no direct-page optimization); errors on
                         unknown mnemonics and out-of-range branches.
    mirage_hfe.py        class MirageHFE(path): read_sector(track, sector) ->
                         bytes, write_sector(track, sector, data). Handles MFM
                         encode/decode, CRCs, ID marks — sectors it writes are
                         readable by real hardware (proven). Internals
                         _scan_track/_track_span/_side0_indices enable raw-flux
                         diffs (see §5 of SAVE_LOAD_EXPERIMENT_LOG.md — the
                         technique that broke every disk deadlock).
    dis6809.py           disasm(mem, start, count, base) -> [(addr, raw, text)].
                         Verify critical branches from the raw displacement
                         bytes; the computed target column is convenience, not
                         gospel.
    build_unified.py     the OS builder — see §3.
    analyze.py           pitch rig: comb + YIN cross-checked estimators, section
                         finder. USE THIS for any pitch claim (octave/subharmonic
                         traps killed two analysis passes — findings §12).
    sideband.py          carrier demodulation: AM depth vs FM deviation separates
                         gain events from phase events; sideband-spacing comb.
    tickgap.py           time-domain click-period fitter (integer-multiple gap
                         fit); the estimator the S220 tick law rests on.
    tickfit.py           modulation-spectrum comb fitter (secondary).
    make_card.py         parameter-card PDF generator (reportlab + pypdf;
                         pip install reportlab pypdf --break-system-packages).
                         Auto scale-search + column-spill check; palette and
                         header text at the top of the file.
    new_params.json      {spec: (spec, value, min, max)} for all 54 params —
                         the audit fixture used to verify PARMTAB builds
                         (S230: +param 76, LFO range).
    DSKA0000_base.hfe    the BASE DISK: blank formatted image, all zeros except
                         the 17-byte RAM vector stub $8000-$8010 on track 0
                         (IRQ/FIRQ/entry JMPs). sha256 4580e4fa6ad868ef6b80e599
                         0de2503023367ebfb4a15cbda1df783e00132977, 2008064 bytes.
                         (Replaced the older stock-derived DSKA0000_slot_d2.hfe;
                         the boot ROM needs only the stub - hardware-confirmed.)

## 2. DISK GEOMETRY

80 tracks, single-sided, 6 sectors/track: sectors 0-4 = 1024 B, sector 5 =
512 B (5632 B/track, ~440 KB/disk). The HFE container is raw MFM; use
MirageHFE, never byte offsets.

    tracks 0-10    the OS (boot ROM loads $8000-$BDFF from these every boot;
                   the load map lives in ROM at $FB80 — see TECHNICAL_FINDINGS
                   Part II §7)
    tracks 11-70   ten Orovela slots (slot s = 6 tracks from 11+6s)
    tracks 71-79   unused
    RE-FLASH WARNING: writing a new OS image blanks tracks 11-79 — slots do
    not survive an OS update.

## 3. BUILDING THE OS

    python3 build_unified.py DSKA0000_<name>.hfe   (S214: also blanks the 10 slot headers)

Assembles os_unified.asm (ORG $9700), asserts the end <= $BDFF, copies the base
disk, overlays the code window onto the OS sectors via SECMAP, regenerates the
$9600 frequency table (equal-tempered, ANCHOR = 1144 * 2^(-22.2/1200) at index
36 = middle C) and the bend-slope tables in the table's unreachable tail
($96C6+). SECMAP (address, track, sector, size):

    $9600 (1,0) 1024   $9A00 (1,1) 1024   $9E00 (1,2) 1024
    $A200 (1,3) 1024   $A600 (1,4) 1024   $AA00 (1,5) 512
    $AC00 (2,5) 512    $AE00 (3,5) 512    $B000 (4,5) 512
    $B200 (5,5) 512    $B400 (6,5) 512    $B600 (7,5) 512
    $B800 (8,5) 512    $BA00 (9,5) 512    $BC00 (10,5) 512

To EXTRACT the code window from any built image (for verification):

    from mirage_hfe import MirageHFE
    h = MirageHFE(path); img = bytearray(0xBDFF-0x9600+1)
    for a,t,s,sz in SECMAP: img[a-0x9600:a-0x9600+sz] = h.read_sector(t,s)

Then disassemble $9700.. with dis6809 and diff (addresses normalized) against
the previous build. The intended changes, nothing else.

## 4. SLOT FORMAT (for slot-management utilities)

Slot s occupies tracks T..T+5, T = 11 + 6*s (slots 0-9 -> tracks 11-70).

SAMPLE: 34 sectors mapping DOC $0000-$7FFF in this exact order (SMTAB):
    rel-tracks 0-3: sectors 0,1,2,3,4,5 each (6 x 4 = 24 sectors)
    rel-tracks 4-5: sectors 0,1,2,3,4 each (5 x 2 = 10 sectors)
    sizes: sec0-4 = 1024 B, sec5 = 512 B -> 24576 + 8192 = 32768 exactly
Sample data is 8-bit unsigned, $80-centered, $00-scrubbed ($00 -> $01; a $00
byte halts an ES5503 oscillator — any INJECTED sample must be scrubbed too).

THE CURSED SECTOR — RESOLVED at S213 / unified147. History: OS builds up to
unified146 never wrote sample sector index 32 (rel-track 5, sector 3 = DOC
$7800-$7BFF) — a static skip inherited from the SL era ("RNF retry storm") —
and their loader concealed the gap by copying the PRECEDING 1 KB over it
($00->$01 scrubbed). That concealment's exit seam is an audible click on
save/load round trips (hardware-confirmed). The cursediag146 diagnostic then
proved the curse was MISATTRIBUTED: DKWSEC wrote idx32 cleanly on the first
attempt on two slots (the era's real culprit was the ROM-JSR bypass race,
TECHNICAL_FINDINGS §8 — the holes moved between runs). unified147 writes and
reads all 34 sectors; full 32 KB round trips byte-true with no concealment.
Consequences for utilities:
  - LEGACY FINGERPRINT: a slot whose idx32 region (bytes 30720..31743 of the
    concatenated sample) is ALL ZEROS is a <=146 save (captured audio can
    never be $00). RENDER it with the old load transform (copy bytes
    29696..30719 over 30720..31743, then scrub $00->$01) — that is what the
    OS that saved it played. INJECTING such audio onto a 147 disk must BAKE
    that concealment into the sectors (147's loader no longer conceals).
  - Slots with real data in idx32 (unified146+ saves) render verbatim
    (scrub only) and copy verbatim.
  - BYTE-EXACT copies (slot backup, .oro) never transform — store raw.
  - The capture-end zero-crossing marker (8 zeros near $7FF8) is present in
    saved audio; every loader's scrub turns it into $01s in DOC RAM.

HEADER at (T+4, sector 5), 512-byte sector, 237 bytes used (v5):
    [0]   $C3   magic (old $A5$5A patch slots can never misparse)
    [1]   $3C
    [2]   $05   version (S232 / Orovela 1.3: v5 = 54-entry param block incl.
                params 76-77. The loader ALSO accepts v4 = 53 entries (Orovela
                1.2; param 77 re-initialized to 0 = on) and v3 = 52 entries
                (sample manager; 76 and 77 re-initialized). Anything else =
                bad load.)
    [3]   flags: bit0 = has-sample
    [4..219]    PARMTAB image, 54 entries x {spec, value, min, max} (v5;
                v4 has 53 entries ending at [215], v3 52 ending at [211], and
                everything below shifts -4 / -8 — the loader derives offsets
                from the count)
    [220..228]  SMPSHFT, SMPPRE, SSTART, SENDPOS, SENDSAV, LMODE, LSTART,
                SENDPG, ENDPG   (v4: [216..224], v3: [212..220])
    [229..236]  SENDSV8 (the 8 sample bytes saved under the end marker)
                (v4: [225..232], v3: [221..228]). NOTE (S226): saves always store UN-rotated
                audio + logical loop points — extraction tools never see a
                rotated buffer.
Sector (T+5, 5) is spare. Save order is audio first, header LAST (an
interrupted save magic-fails to empty rather than half-loading). All-zero
magic = empty slot (the OS regenerates the boot saw). Anything else invalid =
rejected.

Capture-rate metadata -> Hz (SMPSHFT is the playback shift; rate from PARMTAB
spec 1): rate 1 = 3418.8 Hz, rate 2 = 6349.2 Hz, rate 3 = 10256.4 Hz, rate 4 = 15503.9 Hz.
(S233c, exact at E = 2.000 MHz. The S220b figures 3139.9/5831.2/9419.7 below
were 147 cents LOW - the calibration sine was sharp. v0.7 carries the wrong ones.)
(S220b calibration-disk measurement. THE OLD 10644 FIGURE WAS 13% HIGH; any
tool or math still carrying it is wrong. Sample manager v0.7+ is correct.)

## 5. UTILITY RECIPES

LIST SLOTS: for s in range(10): read (11+6s+4, 5); classify by magic bytes
(zero/zero = empty, $C3 $3C = unified v3, $A5 $5A = ancient patch slot).

EXTRACT SLOT -> WAV: read the 34 SMTAB sectors in order, concatenate (32768 B).
If bytes 30720..31743 are ALL ZERO (legacy <=146 save, §4) apply the old load
transform: copy bytes 29696..30719 over them. Scrub $00->$01 throughout either
way. Then subtract 128 -> signed 8-bit (or <<8 for 16-bit), sample rate from
the rate param in the header's PARMTAB image. Loop points: LSTART/ENDPG are
512-byte page numbers.

INJECT WAV -> SLOT: the sample manager (v0.7+ — earlier versions carry the
wrong rate-3 capture rate) does this end to end - see its README. Rules a hand-rolled injector must match: resample to a supported rate,
8-bit unsigned +$80 center, clamp 1..255 (scrub zeros!), pad with $80 to 32768;
PARMTAB from new_params.json defaults with spec 1 = rate, specs 13/15-18
consistent with the page metadata via the SCALE99 inverse v = ceil(64*page/41);
metadata: SMPSHFT=3, SMPPRE = 8/4/2/1 for rates 1/2/3/4 (the LOADER derives the
rate from SMPPRE!), SENDPG/ENDPG pages. One-shot at rates 2-3 needs the 8-zero
end marker at a 256-aligned position past the audio with SENDPOS = pos>>8 and
SENDSV8 = the bytes under it; rate-1 one-shots and LOOPS store NO marker,
SENDPOS=0 (S126/S150 — and since S224 the OS places its own loop-end sentinel
at loop-on from the params; stored audio stays marker-free). Write audio
first, header LAST.

COPY/BACKUP SLOTS: sector-copy the 6-track span (or just the 35 mapped
sectors) between images. Byte-identical round-trips are expected; verify with
a re-read.

VERIFY AN OS IMAGE: extract via SECMAP (§3), compare against a known build
(orovela 1.5 = build 187 on the clean base (image 189): 9911 B, $9700-$BDB6,
sha256 1af38ccf...d7f6;
orovela 1.4 = build 183: 9961 B, $9700-$BDE8, sha256 9eaf87f4...;
orovela 1.3 = build 178: 9922 B, $9700-$BDC1, sha256 03e45545...;
orovela 1.2 = build 175: 9886 B, $9700-$BD9D; build 161 = s225b: 9955 B;
orovela 1.1 = unified148: 9907 B).

## 6. ENVIRONMENT NOTES

python3; pip needs --break-system-packages in the cloud workspace. The card
generator needs reportlab + pypdf; pdftoppm (poppler) renders check images.
HFEs are ~2 MB each — clean up superseded extracts (unifiedNNN.bin) freely;
the HFEs in `disk images` are the archive.
