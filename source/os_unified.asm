; ==========================================================================================
; OROVELA 1.5 (released 2026-10-12) = build 187 (s234d_loopmk187). Over 1.4: boot display on
; param 21 (S234a), boot saw retuned -145c (S234b), one-shot end marker translated with the
; fine-start rotation + loop range clamped at use instead of cascaded (S234c), and the loop-on
; scrub restores the OS end marker instead of erasing it (S234d).
; OROVELA 1.4 (released 2026-10-08) = build 183 (s233e_r4lock183). Over 1.3: sample RATE 4 =
; 2 MHz/129 = 15503.9 Hz (~2.1 s; N=1, latch $7F, resshift 8 at every rate branch, S233), and
; the capture rates corrected to their true values (S233c: 3418.8 / 6349.2 / 10256.4 Hz).
; OROVELA 1.3 (2026-10-06) = build 178: MIDI-in hang fix (S231) + param 77 (S232; header v5).
; ==========================================================================================
; Synthesis engine: 8-voice poly, per-voice amp+filter ADSR, PER-VOICE LFO, velocity.
; Voice struct = 11 bytes. U=struct ptr, B=voice index.
;   0 active  1 key  2 ampst  3 amplv  4 fltst  5 fltlv  6 age  7 apk(amp peak)
;   8 lfophi  9 lfoplo  10 fpk(filter peak)
VBASE   EQU   $8500
VSTRIDE EQU   16                ; voice struct 16 bytes (added OPST/OPLV at 14/15 for pitch env)
KBST    EQU   $8420
KBKEY   EQU   $8421
KBVEL   EQU   $8422
VELFLR  EQU   60               ; S111: velocity floor - the softest the keyboard realistically sends.
;                                Raise it for a lighter touch, lower it if soft notes stop sounding.
AGECTR  EQU   $8423
LFORATE EQU   $8424            ; global LFO rate (param)
LFODEP  EQU   $8425            ; LFO->filter depth (param 65)
; ---- editor/panel state ----
DMODE   EQU   $8426            ; 0=PARAM mode (show number), 1=VALUE mode (show value)
CURIDX  EQU   $8427            ; current parameter index (0..NPARM-1)
SEGCOL  EQU   $842A            ; display multiplex column (0..7), one per main loop
FRESV   EQU   $8428            ; live resonance value (engine reads this)
FFLOORV EQU   $8429            ; filter env floor (= base cutoff)
FCUTV   EQU   $8430            ; base cutoff (param 21)
PMSKH   EQU   $842D            ; scratch: tens digit segment mask (shifted)
PMSKL   EQU   $842E            ; scratch: ones digit segment mask (shifted)
BTNPREV EQU   $842B            ; button debounce latch
BTNCTR  EQU   $842C            ; (free)
RPTCTR  EQU   $842F            ; up/down auto-repeat countdown
NPARM   EQU   45               ; S112: +reverse               ; S103: builder entries (sample tune moved in from MINIT)
NPARM2  EQU   54               ; S232: +MIDI mod wheel receive (#77); S230: +LFO range (#76)               ; S155: +mod wheel damping; live params incl. MIDI channel + sample tune
; PARMTAB: NPARM entries, 4 bytes each {specnum, value, min, max}
; 14 entries * 4 = 56 bytes -> $AC90-$ACC7, clear of SEGTAB $ACD0.
PARMTAB EQU   $8700            ; S210: relocated from $8580 - 52 entries x 4 = 208 bytes no longer
;                                fit below the $864B+ var cluster. $8700-$8BFF is dead stock code
;                                under Orovela (no owners); table now $8700-$87CF. Old $8580-$863F free.
SEGTAB  EQU   $8400            ; 7-seg font (10 bytes) - moved to $ADxx (clear of PARMTAB growth)
VFDEPTH EQU   $840A            ; velocity -> filter cutoff depth (0-99)
; ---- boot-only wave-generation scratch (reusable after boot) ----
; boot-time wave-generation scratch (only used during boot, before synth runs)
; live envelope rate vars (16-bit; set by SYNCP from PARMTAB via RATE16)
AATKV   EQU   $8431            ; amp attack rate (16-bit)
ADECV   EQU   $8433            ; amp decay rate (16-bit)
ARELV   EQU   $8435            ; amp release rate (16-bit)
ASUSV   EQU   $8437            ; amp sustain level (0-255, fraction of peak)
FATKV   EQU   $8438            ; filter attack rate (16-bit)
FDECV   EQU   $843A            ; filter decay rate (16-bit)
FRELV   EQU   $843C            ; filter release rate (16-bit)
FSUSV   EQU   $843E            ; filter sustain level (0-255, fraction of peak)
FDEPTH  EQU   $843F            ; filter env depth (signed, $80=zero)
TUNEOFS EQU   $8440            ; signed semitone offset from base+coarse tune (added to freqtab index)
TUNEFIN EQU   $8441            ; fine tune (signed, 0=zero; sub-semitone freq scaling)
FREQADJ EQU   $8442            ; 16-bit fine-tuned freq word (written to both oscillators)
VIDX    EQU   $8444            ; voice index scratch (avoids stack juggling through fine-tune math)
LFOTMP  EQU   $864B            ; S82: cutoff running-sum scratch. RELOCATED from $8445, where it was
;                                a ONE-byte slot immediately followed by VAMPDEP ($8446) - and FREF
;                                stores it with STD (see "STD LFOTMP" in the cutoff path), a TWO-byte
;                                write. So every cutoff computation that took the LFO/keyboard-
;                                tracking path overwrote VAMPDEP with the low byte of the running
;                                cutoff sum. VAMPDEP is the velocity->amplitude depth, so the damage
;                                landed on note loudness until SYNCP restored it on a later pass:
;                                intermittent, timing-dependent, and impossible to reproduce on
;                                demand. $864B-$864C is boot-cleared and unclaimed.
LFOTMP2 EQU   $864C            ; (reserved: the low byte of the STD LFOTMP pair - do not allocate)
FCEIL   EQU   $864D            ; S85: 8 bytes - per-channel calibrated cutoff ceiling ($864D-$8654)
FCMIN   EQU   $8655            ; S85: ADC minimum seen during a calibration measurement
FCMAX   EQU   $8656            ; S85: ADC maximum seen during a calibration measurement
FCBASE  EQU   $8667            ; S101: quiet-channel ADC swing, measured before each sweep
SUSTAIN EQU   $8657            ; S89: sustain pedal state (0 = up). Set from keyboard status $B8/$B9.
PBACT   EQU   $8658            ; S89: pitch-bend activity countdown - nonzero keeps VIBR rewriting
PBDEV   EQU   $8659            ; S91: signed wheel deviation from rest, dead-banded (-128..+127)
PBMAG   EQU   $865A
MBACT   EQU   $8697            ; S149: 1 = the last bend came from MIDI, not the local wheel
MBDEV   EQU   $8698            ; S149: bend deviation most recently received over MIDI
SMPTHR  EQU   $8699            ; S151: auto-trigger threshold, held across the in-loop capture wait
SMLRTY  EQU   $86A0            ; S161: header-read attempts remaining
PSPREV  EQU   $86A1            ; S209: Play Seq edge latch (panic). In the boot-cleared $8634-$86AB range.
PSTMR   EQU   $86A2            ; S209: panic double-press window countdown (passes)
VRDEP   EQU   $86A3            ; S210: velocity -> resonance depth (raw 0-99, from SYNCP)
ERDEP   EQU   $86A4            ; S210: filter env -> resonance depth (raw, 49 = zero)
LRDEP   EQU   $86A5            ; S210: LFO -> resonance depth (raw 0-99)
RESVW   EQU   $86A6            ; S210: this voice's computed resonance, FREF scratch
INFVAL  EQU   $86A7            ; S211: input-filter cutoff DAC value, from param 3 (INFCALC)
SMPWTC  EQU   $869A            ; S151: bounded wait counter (2 bytes) so listening cannot hang
SMPAUT  EQU   $869C            ; S152: trigger mode captured BEFORE the DOC pointer is set up            ; S91: |PBDEV| for the multiply
PBTMP   EQU   $865B            ; S91: 16-bit scratch for the bend multiply (2 bytes)
PBSLP   EQU   $866A            ; S108: slope for the current bend direction and range (slope*64)
PBACC   EQU   $866B            ; S108: 16-bit accumulator for the range multiply (2 bytes)
RVLAST  EQU   $866D            ; S112: buffer orientation the engine believes is in effect
SP_REV  EQU   14               ; S112: spec number of the reverse parameter
SP_PBR  EQU   $4A              ; S108: spec number of the pitch-bend range parameter
VAMPDEP EQU   $8446            ; velocity -> amp depth (0-99; 0=constant level, 99=full velocity)
VADEF   EQU   $8447            ; velocity->amp deficit scratch (interrupt-safe)
LFOADEP EQU   $8413            ; LFO->amp depth (param 64)
LFOPDEP EQU   $8414            ; LFO->pitch depth (param 66)
LFOSCL  EQU   $8415            ; LFO scale scratch (depth passed to VLFOR per call)
VIBTMP  EQU   $8416            ; vibrato: signed LFO offset scratch
VIBDLT  EQU   $8417            ; vibrato: 16-bit freq delta scratch ($AD17-$AD18)
LFOWAV  EQU   $8419            ; LFO waveform (param 61): 0=tri 1=saw+ 2=saw- 3=square 4=random S&H
LFOTRG  EQU   $841A            ; LFO trigger (param 63): 0=retrigger 1=free-run
MWBASE  EQU   $841B            ; mod wheel: baseline position (wheel must move past threshold from here)
MWPIDX  EQU   $841D            ; selected param index when baseline was set (re-baseline on change)
MWSM    EQU   $869D            ; S155: smoothed wheel position (exponential average)
MWDAMP  EQU   $869E            ; S155: damping shift from param 74 (0 = none)
MWFUNC  EQU   $869F            ; S155: wheel function from param 71 (0 = edit, 1-4 = modulate)
MWVAL   EQU   $841E            ; mod wheel: current reading scratch
MWLASTV EQU   $841F            ; last param value we wrote/saw (detect external button edits)
; ---- sampling engine state ----
SMPSTAT EQU   $8448            ; 0=idle, 1=armed (waiting), 2=recording
SMPREC  EQU   $8449            ; REC button debounce latch
METPK   EQU   $866E            ; S114: input level-meter peak, fast attack / slow decay
METDEC  EQU   $866F            ; S117: peak-decay divider - one count per 8 passes, not per pass
METFRF  EQU   $8670            ; S120: input-filter refresh divider - one refresh per 16 passes
METPB   EQU   $8671            ; S122: port B saved on arming, restored on disarm
; --- S127: MIDI IN. The 6850 has FIRQ entirely to itself (enmirage.cpp: "FIRQ: IRQ from 6850 UART";
;     IRQ carries the FDC, DOC, VIA and cartridge), so receive cannot disturb disk transfers the way
;     an IRQ source would. A byte arrives every 320us at 31250 baud and the ACIA holds only one, so
;     polling the 9ms main loop would drop most of a stream - it has to be interrupt-driven. ---
MIRING  EQU   $8B80            ; S231: 256-byte receive ring $8B00-$8BFF (dead stock code,
;                                no owners - image scan S231). MIRING is the CENTRE: the 8-bit
;                                indices are used as SIGNED accumulator offsets (LDB A,X), so
;                                $80..$7F map to $8B00..$8BFF and the index wraps by itself -
;                                no mask. 255 bytes = 82 ms of a SATURATED wire (was 10 ms).
;                                (S232: the S231 diagnostic counters MIDROP/MIOVR/MIFE/MIHWM at
;                                $8680-$8683 and the panic CC 102-105 report are REMOVED - job done:
;                                overruns 3/22/40 -> 177's FIRQ-open wheel reads; HWM 48 -> this ring.)
; S228b history: 32-byte receive ring at $86C0-$86DF (was 16 at $8680 -
;                                ~14 bytes arrive per pass at full CC1-sweep rate and a pass
;                                stretched by per-pass SYNCP left no headroom; 32 gives ~1.6x).
;                                Indices MIRHD/MIRTL unchanged; contents need no boot clear.
MIRHD   EQU   $8690            ; ring write index (interrupt side)
MIRTL   EQU   $8691            ; ring read index (main-loop side)
MISTAT  EQU   $8692            ; running status byte, 0 = none yet
MIDAT1  EQU   $8693            ; first data byte of the message being assembled
MICNT   EQU   $8694            ; data bytes received so far for this message
SMPBANK EQU   $844A            ; current write bank during capture (0-3)
SMPRDY  EQU   $844B            ; 1 = a sample has been captured/loaded (RAM has data)
GEN0    EQU   $844C            ; sampling scratch
GEN1    EQU   $844D            ; sampling scratch (saved port B)
GEN2    EQU   $844E            ; sampling scratch (mux/source bits)
SMPPBSV EQU   $844F            ; saved port B during capture
SMPACRS EQU   $8450            ; saved VIA ACR during capture
SMPSHFT EQU   $8451            ; playback frequency shift for sample mode (set from rate at capture)
SMPFSH  EQU   $8452            ; freq-shift scratch hi (interrupt-safe, note path)
SMPFSL  EQU   $8453            ; freq-shift scratch lo
SMPPRE  EQU   $8454            ; capture prescaler: timer ticks per stored sample (effective rate)
LVWR    EQU   $8455            ; 8 bytes: last DOC volume written per voice (write-on-change cache).
                               ; Writing the DOC volume register every tick (333Hz) to a PLAYING
                               ; oscillator glitches it = amplitude steps at 333Hz harmonics (the
                               ; buzz). Only writing on change eliminates that during steady sustain.
LFCUT   EQU   $845D            ; 8 bytes: last filter cutoff written to $E410+ch per voice.
LFRES   EQU   $8465            ; 8 bytes: last resonance written to $E408+ch per voice.
SSTART  EQU   $846D            ; sample start: wtptr high byte (256-byte units) set at note-on
SENDPOS EQU   $846E            ; sample-end sentinel position (high byte of buffer offset), 0=none
SENDSAV EQU   $846F            ; saved original byte at the sentinel position (to restore on change)
LMODE   EQU   $8470            ; loop mode live var: 0=one-shot, 1=loop
LSTART  EQU   $8471            ; loop start: wtptr high byte (256-byte units) to restart at on loop
ROTPG   EQU   $8472            ; S226: current buffer rotation in 512B pages (0-63). The 32K
;                                sample is physically rotated LEFT by this many pages so the
;                                loop start sits at DOC offset 0 for the free-run/swap engine.
;                                0 whenever loop is off / pager cases / no sample. (Reuses the
;                                dead LOOPOSC byte - the CPU loop service died with S225.)
SENDSV8 EQU   $8473            ; 8 bytes ($AD73-$AD7A): saved sample data under the 8-zero end marker
LPSCRB  EQU   $86A8            ; S222b: 1 = the sample buffer has been scrubbed of $00 for the
                               ; current loop-on. Boot-cleared ($8634-$86AB range).
FRJIT   EQU   $86AC            ; S189: LFSR state for burst-interval dither
FRBUDG  EQU   $847B            ; filter cutoff DAC write budget for this main-loop pass (mux settling)
; ---- 512-byte paged-swap playback state ----
LFOINC  EQU   $847D            ; S229b: precomputed 16-bit LFO phase increment (curved map,
;                                built in SYNCP - the tick path just ADDDs it; 2 bytes)
R1PAIR  EQU   $847C            ; S228b: 1 = this note-on is a rate-1 one-shot using the 16K
;                                swap->one-shot pair (osc 2V swap base 0 -> osc 2V+1 one-shot
;                                base $4000). Cleared at every note-on routing entry.
;                                ($847D-$8483 ex-VNEXTP still free)
CC1VAL  EQU   $8484            ; S228b: latest received CC1 value <<1 (wheel scale)
CC1PEND EQU   $8485            ; S228b: 1 = CC1VAL unapplied; served once per pass (CC1SRV)
SENDPG  EQU   $8486            ; sample-end PAGE (512B units) - one-shot stop point
ENDPG   EQU   $8487            ; effective end PAGE for the pager: loop end if looping, else sample end
; ---- sample/loop range-constraint (PCLAMP) scratch ----
PC_SS   EQU   $8488            ; working copy of sample-start param value (0-99)
PC_SE   EQU   $8489            ; working copy of sample-end value
PC_LS   EQU   $848A            ; working copy of loop-start value
PC_LE   EQU   $848B            ; working copy of loop-end value
PCCUR   EQU   $848C            ; spec number of the param currently being edited
; ---- detune: 2nd free-run oscillator (osc 16+V) per voice, curved +/-1 octave, on same channel ----
MIX     EQU   $848D            ; live detune mix 0-99 (0 = off / dry)
DTFREQ  EQU   $848E            ; scratch: detuned freq word (2 bytes, hi-first)
DTMP    EQU   $8490            ; scratch: frac / mult temp
DAMT    EQU   $8491            ; live detune amount 0-98 (49 = unison)
MIXP    EQU   $8492            ; primary gain (0-128, from MIX)
MIXD    EQU   $8493            ; detune gain (0-64, from MIX)
DTMP2   EQU   $8494            ; scratch: 16x8 multiply partial
DTDELTA EQU   $8495            ; scratch: detune freq delta (2 bytes, hi-first)
RRDIV   EQU   $8497            ; ticks until the next round-robin filter CV refresh (self-starting)
RRVOICE EQU   $8498            ; round-robin filter-refresh voice index 0-7 (self-masking)
NSHCNT  EQU   $8499            ; scratch: sample-mode playback shift counter (note-on + VIBWRF)
SMPRES  EQU   $849A            ; paged-playback size/res byte for the current sample's rate
LSDES   EQU   $849D            ; S226c: rotation target seen on the previous sync pass. The
;                                walk is DEFERRED until the target repeats across two syncs
;                                (i.e. the edit settled - the <=1s forced resync provides the
;                                second look), so scrubbing loop start costs ONE walk at the
;                                end, not one per step. Not boot-cleared: worst case is one
;                                immediate walk on the first loop-on, the old behavior.
SMPLATCH EQU  $849B            ; calibrated capture T1 latch for the current rate
TRIMV   EQU   $849C            ; live sample-tune factor k (param 6 + 78; 128 = unity, ~13.5c/step)
TRTMP   EQU   $8640            ; scratch for TRIMAP 16x8 multiply (4 bytes). S62: RELOCATED from
;                                $84C0 which collided with keypad state KPDIG-KPACC (latent bug
;                                since unified14). $8634-$86AB is boot-cleared, above PARMTAB.
; S63: telemetry retired (job done: page engine exonerated, SVCCNT=62 MAXPEND=1 exact).
; SVCCNT was $8644            ; S60 telemetry: PGLOAD services since note-on (16-bit). S62:
;                                relocated from $84C4 = the pitch-env rate block (PATKR etc) -
;                                the u19/u20 deposits were env constants, not measurements.
PASSCNT EQU   $8646            ; S60: services within the current PGSERV pass (S62 relocated)
MAXPEND EQU   $8647            ; S60: max services seen in any single pass (S62 relocated)
ZCBEST  EQU   $8648            ; S71: best |byte - $80| found while scanning for the end zero crossing
RRRESC  EQU   $8649            ; S80: slots until the resonance DAC is also refreshed (1 in 8)
MWRAWL  EQU   $864A            ; S81: previous raw mod-wheel ADC reading, for outlier rejection
MWACC   EQU   $865E            ; S93: last ACCEPTED mod-wheel reading (hysteresis reference)
TRIMBAS EQU   $8663            ; S96: sample-tune base for the current rate (from TRIMBTB)
PSUMLST EQU   $8664            ; S99: checksum of the PARMTAB value bytes at the last sync
PSYNCC  EQU   $8665            ; S99: passes remaining before a forced resync
MWMOV   EQU   $8666            ; S100: mod-wheel fine-tracking timer (0 = wheel at rest)
PBRUP   EQU   $96D0            ; S108: bend up-slope table, 24 entries (slope*64), in the freq page
PBRDN   EQU   $96E8            ; S108: bend down-slope table, 24 entries
;                                (NOT 'MWLAST' - that name is already taken at $BE83 by the MIDI
;                                 CC1 change-detect, and this assembler silently accepts duplicate
;                                 labels: the collision resolved both to $BE83 and was caught only
;                                 by disassembling the built image.)
; ---- pseudo-random source (LFSR) + per-voice LFO sample-and-hold ----
RNGSTATE EQU  $849F            ; 8-bit LFSR state (must stay non-zero)
; ---- detune random drift (param SP_DRAND): slow per-voice S&H wander of the detune amount ----
OBASEF  EQU   $84A0            ; 8x2 bytes: per-voice base note freq (hi,lo), for recomputing detune
DRIFTC  EQU   $84B0            ; 8 bytes: per-voice countdown to next drift step
DRAND   EQU   $84B8            ; live drift depth 0-4 (0 = off)
DRAND2  EQU   $84B9            ; 2*DRAND+1 (precomputed span for the random offset)
DTBASE  EQU   $84BA            ; scratch: base freq for DTFREQCALC (2 bytes, hi-first)
DRVOICE EQU   $84BC            ; scratch: voice index held across MUL in DRIFTUPD
DRTMP   EQU   $84BD            ; scratch: random byte held in DRIFTUPD
; ---- keypad direct entry + auto value-display on wheel/keypad activity ----
VTMR    EQU   $84BE            ; value-display settle timer: >0 = temporarily show value (wheel/keypad)
KPTMR   EQU   $84BF            ; keypad inter-digit timer: >0 = next digit appends to current value
KPDIG   EQU   $84C0            ; scratch: pressed digit 0-9
KPLAST  EQU   $84C1            ; param index at last digit (append only if same param)
KPPREV  EQU   $84C2            ; keypad debounce latch (fire once per press)
KPACC   EQU   $84C3            ; keypad accumulator (value being typed, both value & param-number modes)
; ---- pitch envelope (params 51-56) ----
PATKR   EQU   $84C4            ; pitch env attack rate (8-bit step/tick)
PDECR   EQU   $84C5            ; pitch env decay rate
PRELR   EQU   $84C6            ; pitch env release rate
PSUSL   EQU   $84C7            ; pitch env sustain level (0-253)
PDEP    EQU   $84C8            ; pitch env depth magnitude (0-99)
PDIR    EQU   $84C9            ; pitch env direction (0=down, 1=up)
PDTMP   EQU   $84CA            ; pitch env scratch (magnitude held across MUL)
KTRACK  EQU   $84CB            ; keyboard tracking amount, signed (param 23 - 49)
KTSGN   EQU   $84CC            ; keyboard tracking sign scratch
TRANSPOSE EQU $84CD            ; octave transpose, signed semitones (-24..+24 in 12 steps)
TSPPREV EQU   $84CE            ; Sample Upper/Lower debounce latch
LPPREV  EQU   $84CF            ; Load Upper+Lower (param reset) debounce latch
TPUTMP  EQU   $84D0            ; Sample-Upper scan result held across the second SCANC
LSPREV  EQU   $84D1            ; Load Seq / Save Seq debounce latch
LSTMP   EQU   $84D2            ; Load-Seq scan result held across the second SCANC
PATCHBUF EQU  $8C00            ; 1KB disk I/O buffer for the patch (free RAM)
PTRACK  EQU   20               ; disk track for the saved patch (free: OS=0-10, sample=40-46)
SVACR   EQU   $84D3            ; saved VIA ACR across a disk op
SVPCR   EQU   $84D4            ; saved VIA PCR
SVDDRA  EQU   $84D5            ; saved VIA DDRA
SVPORTB EQU   $84D6            ; saved VIA port B
SLOTMODE EQU  $84D7            ; slot picker: 0=normal, 1=save-pending, 2=load-pending
SLOTNUM EQU   $84D8            ; slot picker: selected slot 0-9
SLTPREV EQU   $84D9            ; slot picker: Enter/Cancel debounce latch
DKTRK   EQU   $84DA            ; disk track for the current op (PTRACK + slot)
SLTMP   EQU   $84DB            ; slot picker: SCANC temp (B is clobbered by SCANC)
; --- unified slot save/load (sample + params). Slot s (0-9) = 6 disk tracks starting at 11+6s.
;     Layout per slot (base track T): sample = 32KB in 34 sectors in track order
;     [T..T+3: sectors 0-5 (5x1024+512 each)] + [T+4,T+5: sectors 0-4 (5x1024 each)] = 32768 exactly;
;     header = (T+4, sector 5, 512B): magic $C3 $3C, version, flags(bit0=has sample), PARMTAB(172B),
;     sample metadata (17B). Header written LAST so an interrupted save never leaves a valid slot. ---
SLTRK   EQU   $84DC            ; base track of the slot being saved/loaded (11 + 6*slot)
SMIDX   EQU   $84DD            ; sector loop index 0-33 (also the LED progress value)
SMTPTR  EQU   $84DE            ; 2 bytes: walking pointer into SMTAB (ROM disk calls clobber X)
SMDOC   EQU   $84E0            ; 2 bytes: DOC-window address $0000-$7FFF for the current sector
; --- L1 load state (free block $84E2-$857F, below PARMTAB $8580) ---
SMCNT   EQU   $84E2            ; 2 bytes: byte count of the current load sector (1024 or 512)
SMDEND  EQU   $84E4            ; 2 bytes: DOC end address of the current copy = next SMDOC
HDRMETA EQU   $84E6            ; 17 bytes ($84E6-$84F6): stashed header metadata [176..192] -
DIAGP   EQU   $84F7            ; D2: how far SMLOAD got before exiting
                               ;   PATCHBUF is reused by every sample sector, so the header's
                               ;   metadata must survive the loop; restored AFTER SMPPLAY
VTMOUT  EQU   $A0              ; settle/inter-digit timeout in env ticks (~0.48s at ~333Hz)
                               ; FREF runs every main-loop pass (thousands/sec); constantly
                               ; re-strobing the CEM3328 DAC/S&H injects switching noise = the buzz.
                               ; Write-on-change stops re-strobing when the value is steady. Both
                               ; caches are invalidated at note-on so a new note re-establishes them.
; param indices
; ---- parameter SPEC NUMBERS (the displayed param number, in hex) ----
; SYNCP looks up each engine var by these. To RENUMBER a param: change its EQU here AND the
; specnum byte in its PARMTAB build entry. To REORDER the UI: just reorder the PARMTAB entries
; (display walks physical order); SYNCP is unaffected because it looks up by spec number.
SP_CUT  EQU   21               ; cutoff
SP_SSTART EQU 15                ; sample start (0-99 -> position in the 32KB buffer, 256-byte units)
SP_SEND EQU   16               ; sample end (0-99 -> position; a 0x00 sentinel stops playback here)
SP_LMODE EQU  13               ; loop mode (0=one-shot, 1=loop)
SP_LSTART EQU 17               ; loop start (0-99 -> position; playback returns here at loop end)
SP_LEND EQU   18               ; loop end (0-99 -> position; a 0x00 sentinel triggers the loop restart)
SP_MWEN EQU   72               ; S155: mod wheel FUNCTION (0=edit selected param, 1-4 = modulate)
SP_RES  EQU   22               ; resonance
SP_KTRK EQU   23               ; keyboard tracking (filter cutoff follows note)
SP_LFOR EQU   62               ; LFO speed
SP_LFORNG EQU 76               ; S230: LFO range (0=low 1=high) - appended AFTER the 71-75
;                                control group so v3 slot headers stay byte-aligned
SP_LFOD EQU   65               ; LFO->filter depth
SP_LFOA EQU   64               ; LFO->amp depth
SP_LFOP EQU   66               ; LFO->pitch depth
SP_LFOW EQU   61               ; LFO waveform
SP_LFOT EQU   63               ; LFO trigger (retrigger/free-run)
SP_AATK EQU   31               ; amp attack
SP_ADEC EQU   32               ; amp decay
SP_ASUS EQU   33               ; amp sustain
SP_AREL EQU   34               ; amp release
SP_FATK EQU   41               ; filter attack
SP_FDEC EQU   42               ; filter decay
SP_FSUS EQU   43               ; filter sustain
SP_FREL EQU   44               ; filter release
SP_FDEP EQU   45               ; filter env depth
SP_PATK EQU   51               ; pitch env attack
SP_PDEC EQU   52               ; pitch env decay
SP_PSUS EQU   53               ; pitch env sustain
SP_PREL EQU   54               ; pitch env release
SP_PDEP EQU   55               ; pitch env depth
SP_PDIR EQU   56               ; pitch env direction
SP_VFD  EQU   24               ; velocity -> filter depth
SP_VAMP EQU   35               ; velocity -> amp depth
SP_BASE EQU   7                ; base note (MIDI note for recorded pitch)
SP_CRS  EQU   8                ; coarse tune (0-48, 24=zero, +-24 semitones)
SP_FINE EQU   9                ; fine tune (0-98, 49=zero, sub-semitone)
SP_MWDMP EQU  73               ; S155: mod wheel damping (0-3)
SP_DETUNE EQU 10               ; (kept name) detune MIX: 0=dry, higher blends the 2nd osc in
SP_MIX  EQU   10               ; param 17 = detune mix (dry<->detuned blend), 0 = off
SP_DAMT EQU   11               ; param 18 = detune amount, 0-98, 49=unison, curved to +/-1 octave
SP_DRAND EQU  12               ; param 19 = detune random drift depth (0-4; 0 = off)
; S210 new params (see claude_PARAM_MAP.md):
SP_VRES EQU   25               ; velocity -> resonance depth
SP_ERES EQU   46               ; filter env -> resonance depth (49 = zero, bipolar)
SP_LFRS EQU   67               ; LFO -> resonance depth
SP_PWDIS EQU  75               ; pitch wheel disable (0 = enabled, 1 = disabled)
RESMAX  EQU   177              ; S210: resonance DAC ceiling = SCALERES(99). Self-osc onset on
;                                this unit ~166 raw, chaos ~205+: 177 keeps singing reachable in
;                                the top few param steps and the chaos zone unreachable.

OACT    EQU   0
OKEY    EQU   1
OAST    EQU   2
OALV    EQU   3                ; amp level (high byte = audible level)
OALVL   EQU   4                ; amp level low byte (16-bit accumulator)
OFST    EQU   5
OFLV    EQU   6                ; filter env level (high byte)
OFLVL   EQU   7                ; filter env level low byte
OAGE    EQU   8
OAPK    EQU   9
OLFPHI  EQU   10
OLFPLO  EQU   11
OFPK    EQU   12
OLFRND  EQU   13               ; per-voice LFO sample-and-hold random value (LFO waveform 4)
OPST    EQU   14               ; pitch env state (0=idle 1=atk 2=dec 3=sus 4=rel)
OPLV    EQU   15               ; pitch env level (8-bit)

AATK    EQU   $0C
ADEC    EQU   $04
AREL    EQU   $03
FATK    EQU   $0A
FDEC    EQU   $06
FREL    EQU   $05
FFLOOR  EQU   $30
FRES    EQU   $50

        ORG   $9700
OSENTRY
        ORCC  #$50
        LDS   #$BF80
        LDD   #$8038
        TFR   A,DP
        LDA   #$FF              ; oscillator-enable. S217 probe result: $FF and $3E are IDENTICAL
                                ; on this silicon (pitch matched to 0.1 cent, tick line within
                                ; noise) - MAME's both-decode-to-32 model is right. $FF stays as
                                ; the value proven across the capture era.
        STA   $ECE1
; S57: dedicated idle-clock oscillator. The DOC's ADC (wheels + capture input) and DOC-RAM CPU
; access need at least one RUNNING oscillator for clocking; before S56 that was provided by lucky
; leftover stragglers, which SMPQSC's quiesce removed - killing the MOD WHEEL after the first
; capture. Osc 31 (unused by the voice engine: pairs 0-15, detune 16-23) now free-runs permanently:
; volume 0, 32K table at wtptr 0, freq word $4000 (fast ~ms cycle, per the S56 coupling insight),
; IE off. Nothing else may ever write osc 31's registers.
        CLR   $EC5F             ; osc 31 volume = 0
        CLR   $EC9F             ; osc 31 wtptr = 0
        LDA   #$38
        STA   $ECDF             ; osc 31: 32K table
; S72: frequency word 1, not $4000. The idle clock only has to make the DOC fetch RAM every scan -
; which it does at ANY frequency - but its 24-bit accumulator wraps every 2^24/freq cycles, and at
; $4000 that is 1024 cycles = ~32ms = ~30Hz. Measured on hardware: brightness spikes on the DEFAULT
; SYNTH WAVE at gaps of 32.4/32.4/32.4/32.5ms and multiples, i.e. exactly this wrap. S58 predicted
; 28.7Hz for this oscillator before any of it was observed. Osc 31 also shares CHANNEL 0 with voice
; 0, and the 5503's per-channel sample-and-hold takes the last oscillator written (not a sum), so
; its wrap lands squarely on voice 0's output. At word 1 the wrap moves to roughly 11 minutes and
; the read address barely advances, so there is nothing periodic left to inject.
        LDA   #$01
        STA   $EC1F             ; freq lo = 1
        CLR   $EC3F             ; freq hi = 0  -> word $0001
        CLR   $ECBF             ; control: free-run, RUNNING, ch0, IE off
; S90: the pedal state and the bend-activity counter are plain RAM and are NOT cleared by anything
; at boot. SUSTAIN came up holding garbage, so every note-off parked its voice in the sustain state
; and notes hung indefinitely until the pedal was pressed and released once (Viz, unified48).
        CLR   SUSTAIN
        CLR   PBACT
        CLR   MBACT             ; S149: no MIDI bend received yet
        CLR   MBDEV
        CLR   PSYNCC            ; S99: force a sync on the first pass
        CLR   MWMOV             ; S100: wheel starts at rest
        CLR   CC1PEND           ; S228b: no received wheel value pending
        CLR   LFOINC
        CLR   LFOINC+1          ; S229b: LFO holds still until the first param sync
        CLR   MWSM              ; S155: 0 = unseeded; the first wheel read seeds it
        CLR   MWDAMP
        CLR   MWFUNC
        LDA   #78
        STA   TRIMBAS           ; S96: neutral base until a rate is chosen by capture or load
        LDA   #WHTXDIV
        STA   WHTXC             ; S92: MIDI bend transmit countdown
        JSR   FCAL              ; S85: per-channel cutoff-ceiling calibration (see routine)
        JSR   PRELINIT          ; owned DAC init (replaces leftover stock autotune at $B96E:
                                ; it read/wrote a 77-byte-stride struct table at $B050 - inside our
                                ; relocated region - poking 8 live code/data bytes at every boot)

        LDA   $E200
        ANDA  #$FC
        STA   $E200
        JSR   GENWAVE          ; S156: build the default sawtooth into DOC RAM $0000

; ---- configure oscillators 0-15: halted, wtptr $00, 32768-sample table, zero freq and volume ----
        CLRB                     ; oscillator 0
OINIT
        LDX   #$ECA0
        LDA   #$01              ; control = halt
        STA   B,X
        LDX   #$EC80
        LDA   #$00              ; wtptr = $00 -> DOC RAM $0000 (32768-sample buffer)
        STA   B,X
        LDX   #$ECC0
        LDA   #$38              ; T=7 (32768-sample wavetable) - holds the synth wave or a sample
        STA   B,X
        CLRA
        LDX   #$EC00
        STA   B,X
        LDX   #$EC20
        STA   B,X
        LDX   #$EC40
        STA   B,X
; control = (channel<<4) | $01(halt). channel = osc>>1 (voice).
        TFR   B,A
        LSRA                    ; A = osc>>1 = voice/channel
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = channel<<4
        ORA   #$01              ; keep halt bit set: osc configured but STOPPED until note-on
        LDX   #$ECA0
        STA   B,X
        INCB
        CMPB  #$10              ; 16 oscillators (2 per voice x 8) - matches the clean working build
        BNE   OINIT

; --- silence the UNUSED oscillators 16-31. We enable all 32 oscillators ($ECE1=$FF), but only use
;     0-15 (8 voices x 2). The ES5503 sums the HIGHEST enabled oscillator (osc 31) into the mix 3x
;     (es5503.cpp: extra DOC cycles land on osc m_oscsenabled-1). Left uninitialized, oscs 16-31 keep
;     power-on garbage volume + wavetable data, and osc 31's garbage - tripled - is chaotic noise
;     (the buzz). Halt them and zero their volume so they contribute nothing. The stock OS has no buzz
;     because it clears all oscillator volumes; we were only clearing 0-15. ---
        LDB   #$10              ; start at oscillator 16
OINITHI
        LDX   #$ECA0
        LDA   #$01              ; control = halt
        STA   B,X
        LDX   #$EC40
        CLR   B,X               ; volume = 0
        LDX   #$EC00
        CLR   B,X               ; freq lo = 0
        LDX   #$EC20
        CLR   B,X               ; freq hi = 0
        LDX   #$EC80
        CLR   B,X               ; wtptr = 0 (page 0, 32K buffer) - detune oscs (16-23) play the sample
        LDX   #$ECC0
        LDA   #$38              ; size/res = T7 (32768-sample wavetable) - matches oscs 0-15
        STA   B,X
        INCB
        CMPB  #$20              ; through oscillator 31
        BNE   OINITHI

; clear voice structs (112 bytes = 14*8)
        LDX   #VBASE
        LDB   #128
CLRV    CLR   ,X+
        DECB
        BNE   CLRV
        CLR   AGECTR
        CLR   KBST
; seed the pseudo-random generator (must stay non-zero); OLFRND is a voice-struct field, so it is
; cleared by the voice-struct clear above.
        LDA   #$A5
        STA   RNGSTATE
        LDX   #DRIFTC
        LDB   #8
CLRDC   CLR   ,X+
        DECB
        BNE   CLRDC
; LFO params (defaults)
        LDA   #$04
        STA   LFORATE
        LDA   #$18
        STA   LFODEP

; ---- panel/editor init ----
        LDA   #$1F
        STA   $E203             ; DDRA: bits0-4 out, 5-7 in (panel)
        LDX   #FONT
        LDY   #SEGTAB
        LDB   #10
PFCOPY  LDA   ,X+
        STA   ,Y+
        DECB
        BNE   PFCOPY
        CLR   DMODE             ; start in PARAM mode
        LDA   #18               ; S234: boot on param 21 (filter cutoff) - PARMTAB index 18
        STA   CURIDX            ; (entries 1-18 precede it). Was CLR = param 1. MWPIDX=$FF
                                ; below still makes the wheel re-baseline (pickup) first.
        CLR   SEGCOL
        CLR   BTNPREV
        CLR   BTNCTR
        CLR   KPPREV
        CLR   KPTMR
        CLR   VTMR
        CLR   TRANSPOSE
        CLR   TSPPREV
        CLR   LPPREV
        CLR   LSPREV
        CLR   RPTCTR
        LDA   #$FF
        STA   MWPIDX            ; invalid param -> first MWSERV pass re-baselines (power-on safe)
        CLR   MWVAL
        CLR   MWBASE
        CLR   MWLASTV
        CLR   SMPSTAT           ; sampling idle
        CLR   SLOTMODE          ; slot picker idle
        CLR   SLOTNUM
        CLR   SLTPREV
        CLR   SMPREC
        CLR   SMPRDY
        CLR   SENDPOS           ; no sample-end sentinel placed yet
        CLR   SSTART            ; sample start = buffer origin
        CLR   LMODE             ; loop mode off (one-shot)
        CLR   LSTART            ; loop start = buffer origin
        CLR   ROTPG             ; S226: buffer starts unrotated
        LDA   #3
        STA   SMPSHFT           ; default playback shift (S49: the note path and VIBWRF honor this)
; build PARMTAB: {specnum, value, min, max} x NPARM.
; ENTRIES ARE IN NUMERICAL SPEC ORDER (this defines the UI display order). To reorder the UI,
; reorder these entries - SYNCP is unaffected (it looks up by spec number via PFIND).
        JSR   PBUILD            ; load all parameter defaults into PARMTAB

; VIA Timer1
        LDA   $E20B
        ORA   #$40
        STA   $E20B
        LDA   #$70
        STA   $E208
        LDA   #$17
        STA   $E209

        JSR   CA2ACK
        LDA   $E20A
        JSR   CA2ACK

        JSR   MINIT             ; init all engine vars (incl. tuning) before first note
MAIN
        JSR   PSYNC             ; S99: sync engine vars from PARMTAB, but only when something changed
        JSR   MIDIN             ; S127: drain and interpret anything received
        JSR   KBMIDI            ; keyboard ack #1 (start of pass)
; --- display: the old PANEL full-sweep lit all segments at the top of the pass, then left the display
;     idle (holding one segment) through SYNCP/FREF/TICKALL/PGSERV = the digits saw only ~2% duty =
;     the dim we see. Now SEGREF (below, inside FREF) lights ONE segment per voice, so the display keeps
;     multiplexing THROUGH the filter loop. The 8x SEGREF DOES lengthen the pass, which lowered the
;     once-per-pass keyboard ack rate (R6500/11 delivers one byte per ack) - the fix is to ack the
;     keyboard several times per pass (below), spread across the pass so the controller has time to
;     shift the next byte in between calls. Button scan is moved just before the filter loop.
; S122: no wheel service while armed. Port B carries BOTH the audio mux and the wheel ADC channel
; select, so the wheels and the meter cannot share it - see the SMPRD1 note below.
        LDA   SMPSTAT
        CMPA  #$01
        BEQ   MWSKIP
        JSR   MWSERV            ; mod wheel -> current param value (pickup mode)
MWSKIP
        JSR   KBSERV            ; keyboard ack #2
        JSR   PCLAMP            ; enforce sample/loop range constraints on the just-edited value
        JSR   SMPSERV           ; sampling: REC button + arm/record state machine
        JSR   BTNSCAN           ; PARAM/VALUE/up/down buttons (was inside PANEL). BTNSCAN briefly drives
                                ; $E20F with its scan pattern; FREF's first SEGREF overwrites it at once.
        JSR   KPSCAN            ; numeric keypad -> direct value entry
        JSR   MOCTHK            ; Sample Upper/Lower -> octave transpose
        JSR   LPSCAN            ; Load Upper+Lower -> reset all params to defaults
        JSR   LSSCAN            ; Load Seq / Save Seq -> patch load / save
        JSR   PSSCAN            ; S209: Play Seq x2 -> panic (release every voice)
        JSR   SLOTSRV           ; slot picker: Enter executes, Cancel aborts
        JSR   KBSERV            ; keyboard ack #3 (just before the long FREF stretch)
; ---- filter refresh: every pass - resonance fixed, flat per-voice cutoff ----
        LDU   #VBASE
        CLRB
; S186: ONE write per pass, every pass, cycling continuously through all eight channels.
; filter12 cured the drift (-0.1 dB) but buzzed exactly as much as filter9 (+17.8 dB) despite a
; QUARTER of the write rate. So buzz depth does not scale with rate at all - what both builds shared
; was firing eight writes BACK TO BACK inside a single pass, with no settling between mux strobes.
; The loudest non-harmonic component sat at 357 Hz in both, against 1266 Hz in every clean build.
; That is exactly what S80's one-write-per-pass budget was for: separating consecutive strobes by a
; full loop body. I removed it as a rate limiter when it was really a SPACING limiter.
; So: keep the cache off so every channel is genuinely re-driven, keep writing inactive channels so
; the mux keeps cycling, but serve only ONE write per pass. A full eight-channel cycle then takes
; ~72ms - between filter12's 36ms, which cured the drift, and unified133's 209ms, which did not -
; at an eighth of filter12's instantaneous strobe density.
; S187: back to filter12's BURST - eight writes in quick succession every fourth pass - because the
; burst is what cures the drift. Spreading them one per pass failed at 72ms (filter13, +9.2 dB) while
; bursting worked at both 9ms and 36ms, so it is the succession that matters, not the repetition rate.
; S191: the burst gate is GONE - one write per pass, every pass, exactly unified133's quiet
; schedule. filter17 kept the gate by mistake, so it tested the preload PLUS a burst and its
; artefact sat at the gate rate (~24 Hz with harmonics at 46, 71 and 95). Drift did improve, 9.3 to
; 3.6 dB, which says the preload is doing real work - but it has never yet been tested on its own.
; S194: BURST ALL EIGHT, as stock does. Its loop at $8A5E walks the eight voice records and
; $E418-$E41F back to back, four writes per channel through $F5E7 - preload, cutoff, preload,
; resonance. That is 32 writes per burst, four times filter12's eight, and stock is flat AND clean,
; so the buzz was never the write count.
; The preload is the likely reason: loading the DAC first means the strobe samples a SETTLED value,
; while strobing alone connects the hold to a DAC mid-slew - a wrong value AND a glitch.
;   filter12 burst without preload -> flat, buzzy
;   filter20 preload without burst -> clean, drifty
; This build is both, which is what stock actually does.
; S195: burst EVERY pass, not every fourth. The grid now reads:
;     burst every pass,  no preload (filter9)  -> drift 0.0 dB, buzz +17.8 dB
;     burst every 4th,   no preload (filter12) -> drift 0.1 dB, buzz +16.7 dB
;     burst every 4th,   preload   (filter21)  -> drift 5.2 dB, buzz  +3.4 dB
; The preload cut the buzz by 13 dB, which is what it was predicted to do - the strobe now samples a
; settled DAC. It also halved the cure, because a burst every fourth pass is slower than the drift
; needs once the values are landing properly. This is the remaining corner: filter9's rate with
; filter21's preload.
; S205: back to ONE channel per pass. The schedule is not the lever - the CHARGE TIME is.
; S207 (unified138): STOCK-EXACT. The re-audit (claude_FILTER_REAUDIT.md) disassembled stock's
; actual burst at $8A5E: per channel it is ROM $F5E7 = preload($E418+ch)/connect($E410+ch) for
; cutoff then preload/connect($E408+ch) for resonance, all 8 channels back-to-back — and then a
; terminal CLRA / STA $E41F: DAC parked at ZERO with the select latch in the $E418 range = BOTH
; CD4051 inhibits asserted (the 74LS174 latches A0-A4 -> FS0-FS4; FS3/FS4 are the two sections'
; inhibits — five lines, not four). Between bursts NOTHING tracks the DAC and the DAC rests at 0.
; No prior build ever did the park; every flat build accidentally approximated it (last write = an
; inactive channel's zero), every drifting build left the DAC resting on a sounding value.
; So: write-on-change, the per-pass budget and the caches are GONE; every pass bursts all eight
; channels stock-style and parks. Cadence = every pass (~111 Hz), the rate filter9/25 proved cures
; the drift; stock gates on a timer flag but its exact tick is in the unavailable stock region.
FREF
        JSR   SEGREF            ; light one display segment for this voice, advancing SEGCOL 0..7.
                                ; 8 voices = one full display refresh spread across the filter loop, so
                                ; each segment stays lit for a whole voice iteration. Preserves B and U.
; Filter drive: $E408+ch and $E410+ch. The cutoff/resonance polarity of these two is AMBIGUOUS in
; the available references (MAME's memory-map comment and its own decode logic contradict each other),
; so this mapping is treated as empirically validated and must be confirmed on hardware, not guessed.
; Current mapping: FRESV -> $E408, cutoff -> $E410 (the project's prior "CORRECTED" mapping).
; --- write-on-change (per voice): FREF runs every main-loop pass. Re-strobing the CEM3328 DAC/S&H
;     every pass injects switching noise into the analog filter control voltage = the buzz. Only
;     write a channel's register when ITS value changes. LFRES[voice]/LFCUT[voice] hold the last
;     values written; on a steady note nothing changes so the DAC is left alone. ---
; S121: while ARMED, skip the filter writes entirely - but NOT the SEGREF call above, which the
; meter's own display depends on. THE INPUT FILTER IS CHANNEL 7: $E40F/$E417/$E41F are the channel-7
; registers of the resonance, cutoff and preload blocks, and the voices use channels 0-7 - so the
; input filter is physically voice 7's filter. That is exactly why SMPCAP quiesces the oscillators
; before recording; the filter is only free once the voices stop using it.
; Silencing the voice VOLUMES in S118 was not enough: FREF kept writing voice 7's cutoff over the
; meter's setting, driving it near the ceiling where it sings. And as more keys are held the refresh
; rotation reaches channel 7 differently, shifting the CV and with it the oscillation frequency -
; exactly the "frequency drops the more keys I hold down" that Viz observed.
        LDA   SMPSTAT
        CMPA  #$01
        LBEQ  FRWRSK            ; armed -> skip to the loop tail; SEGREF above still ran
; S207: the per-voice resonance write-on-change block is gone — resonance now goes out with the
; cutoff in the stock-order 4-store block at FRWRCAP, every voice, every pass, like stock.
        LDA   OACT,U
        LBEQ  FRSKIP            ; inactive voice -> cutoff 0, base resonance
; ---- S210: per-voice RESONANCE = base + velocity + filter-env + LFO, clamped 0..RESMAX ----
; Mirrors the cutoff pipeline below term for term (same idioms, same shift counts). Computed here,
; before the cutoff math claims A, and parked in RESVW for the 4-store block. B = voice index and
; must survive: saved around the block. The 16-bit running sum lives on the stack, exactly like the
; cutoff's velocity term.
        PSHS  B
        LDB   FRESV             ; base resonance (0..RESMAX via SCALERES)
        CLRA
        PSHS  A,B               ; running sum
; velocity term: (OFPK-$80) * VRDEP >> 7
        LDA   OFPK,U
        SUBA  #$80
        BLS   RSV0
        LDB   VRDEP
        MUL
        TFR   A,B
        ASLB                    ; product >> 7
        CLRA
        ADDD  ,S
        STD   ,S
RSV0
; filter-env term: OFLV * (ERDEP-49) >> 6, signed
        LDA   ERDEP
        SUBA  #49
        BEQ   RSE0
        BMI   RSEN
        LDB   OFLV,U
        JSR   MSH6           ; S226R: MUL + >>6 shared. D >>= 6
        ADDD  ,S
        STD   ,S
        BRA   RSE0
RSEN
        NEGA                    ; |depth|
        LDB   OFLV,U
        JSR   MSH6           ; S226R: MUL + >>6 shared
        NEGA                    ; negate 16-bit (the cutoff env's exact idiom)
        NEGB
        SBCA  #$00
        ADDD  ,S
        STD   ,S
RSE0
; LFO term: VLFOR scaled by LRDEP (same per-voice phase/waveform as the cutoff LFO, own depth)
        LDA   LRDEP
        BEQ   RSL0
        JSR   LFOSC             ; LFOSCL = LRDEP scaled (clobbers A,B; the sum is safe on the stack)
        JSR   VLFOR             ; A = signed LFO offset (preserves B and U)
        TFR   A,B
        SEX
        ADDD  ,S
        STD   ,S
RSL0
        PULS  A,B               ; D = summed resonance
        TSTA
        BMI   RSCLZ             ; went negative -> 0
        BNE   RSCLM             ; >255 -> ceiling
        CMPB  #RESMAX
        BLS   RSCLK
RSCLM
        LDB   #RESMAX
        BRA   RSCLK
RSCLZ
        CLRB
RSCLK
        STB   RESVW
        PULS  B                 ; restore voice index
; ---- end S210 resonance block; the cutoff pipeline below is unchanged ----
        PSHS  B                 ; protect voice index across 16-bit math
; signed env depth: FDEPTH is 0..98, midpoint 49 = zero. depth = FDEPTH-49 (-49..+49).
        LDA   FDEPTH
        SUBA  #49
        LBEQ  FRENV0            ; depth 0 -> no env contribution
        BMI   FRENVNEG
; positive depth: contribution = (OFLV * depth) >> 6
        LDB   OFLV,U
        JSR   MSH6           ; S226R: MUL + >>6 shared. D = OFLV*depth ; D >>= 6
        BRA   FRENVADD
FRENVNEG
        NEGA                    ; |depth|
        LDB   OFLV,U
        JSR   MSH6           ; S226R: MUL + >>6 shared. D >>= 6 magnitude
        NEGA                    ; negate 16-bit
        NEGB
        SBCA  #$00
        BRA   FRENVADD
FRENV0
        CLRA
        CLRB
FRENVADD
; D = signed env contribution. add base cutoff FCUTV (unsigned).
        ADDB  FCUTV
        ADCA  #$00              ; D = base + env (signed 16-bit)
; add velocity->cutoff: (OFPK-$80) * VFDEPTH >> 7. OFPK is $80..$FF (vel-derived), so
; (OFPK-$80) is 0..$7F. Brighter with higher velocity, scaled by VFDEPTH param.
        PSHS  A,B               ; save running sum (16-bit)
        LDA   OFPK,U
        SUBA  #$80              ; A = velocity component 0..$7F
        BLS   FRVELDONE         ; <=0 -> no velocity contribution
        LDB   VFDEPTH
        MUL                     ; D = velComponent * VFDEPTH
        TFR   A,B               ; B = product>>8
        ASLB                    ; B = product>>7
        CLRA                    ; D = velocity contribution (0..~98)
        ADDD  ,S                ; add running sum
        STD   ,S                ; update running sum on stack
FRVELDONE
        PULS  A,B               ; D = base + env + velocity
; ---- LFO -> filter cutoff: add LFO offset scaled by LFODEP (param 65) ----
; LFODEP=0 -> skip. The voice index is on the stack (restored at FRDONE); VLFOR's internal
; PSHS/PULS B is balanced so the stacked voice index survives. Running sum stashed in LFOTMP.
        TST   LFODEP
        BEQ   FRKTRK            ; filter LFO depth 0 -> skip LFO, still do keyboard tracking
        STD   LFOTMP            ; stash running cutoff sum (interrupt-safe scratch)
        LDA   LFODEP
        JSR   LFOSC             ; LFOSCL = LFODEP scaled (255 at param 99)
        JSR   VLFOR             ; A = signed LFO offset
        TFR   A,B
        SEX                     ; D = sign-extended LFO offset
        ADDD  LFOTMP            ; running sum + LFO
FRKTRK
; ---- keyboard tracking: add signed cutoff offset (param 23) that scales with note distance ----
        TST   KTRACK
        BEQ   FRCLAMP           ; tracking off (param 23 = 49)
        STD   LFOTMP            ; stash running sum
        JSR   KTRKOFF           ; D = signed tracking offset
        ADDD  LFOTMP            ; running sum + tracking
FRCLAMP
; clamp to 0..255: if hi byte negative -> 0; if hi byte >0 -> 255; else low byte.
        TSTA
        BMI   FRZERO
        BNE   FRMAX
        TFR   B,A
        BRA   FRDONE
FRZERO
        CLRA
        BRA   FRDONE
FRMAX
        LDA   #$FF
FRDONE
        PULS  B                 ; restore voice index
        BRA   FRWR
FRSKIP
; S170 note: filter2 tests SKIPPING this write entirely. Kept as-is on the mainline until that
; result is in.
; (diagnostic text retained for reference)
;   S170 DIAGNOSTIC: an inactive voice's cutoff is now LEFT ALONE instead of being written as zero.
; With default parameters every active voice computes the SAME cutoff - envelope depth 49 is zero,
; keyboard tracking is off, LFO to filter is zero - so the only value that differs anywhere in the
; refresh is the ZERO written for inactive voices. If a voice's active flag is momentarily wrong, an
; audible channel gets zeroed and holds it until the next refresh: a dip of exactly one refresh
; interval, which is what Viz measured.
; It is also a pointless write. An inactive voice makes no sound, so its filter setting cannot be
; heard, and skipping it lowers the write rate as a bonus.
; The note-on path already invalidates LFCUT for a voice it takes over (S87), so a stale cache
; cannot leave a re-used voice unwritten.
; S183: inactive voices are not written at all. They make no sound, so their filter setting cannot
; be heard, and every write skipped is buzz not generated. With ONE note held that removes seven of
; the eight writes per pass outright.
; S185: inactive channels are written AGAIN. filter11 proved they matter - skipping them brought the
; drift back to 8.0 dB with everything else identical to filter9's 0.0 dB. One DAC feeds eight
; sample-and-holds through a multiplexer that PARKS on the last channel written, so writing all
; eight is what keeps the mux cycling and every hold topped up. Writing only the sounding voice
; leaves the mux parked and the holds decaying.
; S188: inactive voices skipped again - the park write below is what keeps the mux off the
; sounding channel, so writing all eight is no longer needed for that purpose
; S202: inactive voices are SKIPPED again. Holding one note, seven of the eight writes were for
; silent voices - pure artefact. filter11 showed that writing only the sounding voice drifts,
; because the multiplexer then parks on it; the park write after the loop handles that with ONE
; extra strobe instead of seven.
; S203: an inactive channel is written with ITS OWN BASE CUTOFF, not zero and not skipped.
; filter26 proved all eight must be written every pass - active-only plus a park write drifts 9.1 dB
; while writing all eight gives 0.4 dB, stock parity. So the mux must cycle through every channel.
; But we sent ZERO to the silent ones, so the DAC lurched 158 -> 0 -> 158 -> 0 eight times a pass.
; That is almost certainly the buzz: stock writes MORE registers than we do and stays clean, because
; its values do not jump around.
; What reaches a silent channel is inaudible by definition, so sending it the same number the
; sounding channels get costs nothing and keeps the DAC nearly still.
; B still holds the voice index here - FRESSK branches in before it is pushed.
; S204: back to writing ZERO for an inactive channel. filter27 sent it the channel's own base cutoff
; instead, reasoning that a silent voice's filter setting is inaudible - and it produced DROPOUTS of
; 40ms to 1.65s, 43 to 70 dB deep, recurring unpredictably. So the zero is doing something I do not
; understand, and I am not going to guess at it while it costs playability.
        LDA   FRESV             ; S210: inactive voice -> BASE resonance (steady value, no lurch)
        STA   RESVW
        CLRA
FRWR
; The CEM3328 self-oscillates at very high cutoff (hardware note: cutoff 99 rings even at low
; resonance). With all 8 voice filter channels parked near max cutoff, slight analog variation between
; them makes some sporadically tip into self-oscillation - a sine at the (high) cutoff frequency (the
; piercing tones), more likely with more notes held. So we CAP the cutoff value written to the DAC at
; a ceiling just below the oscillation threshold. This keeps nearly all the brightness and the full
; 0-99 param range (99 now = brightest-safe), and does NOT affect the capture input filter (a separate
; channel). If the ringing persists, lower CUTMAX; if you want more brightness and it's quiet, raise it.
CUTMAX  EQU   $D0               ; S102: fallback ceiling when a channel NEVER oscillates during the
;                                sweep, raised $B0 -> $D0. If FCAL walked all the way to $E0 without
;                                detecting anything, that channel demonstrably does not oscillate
;                                below $E0, so holding it down at $B0 threw away range for nothing.
;                                Previously: 176/255 ~ 69%.
                                ; S84: lowered from $C0. Hardware-measured at $C0 with RESONANCE 0 and
                                ; cutoff 99, repeated Cm chords: some strikes carried narrow tones at
                                ; 4078 Hz and 4422 Hz - not chord harmonics, 8.2x and 5.1x prominence
                                ; over their neighbourhoods - while other strikes had nothing above
                                ; 608 Hz. Two distinct frequencies = two voices oscillating at their
                                ; own cutoffs, i.e. exactly the per-channel analog spread described
                                ; below. Non-harmonic energy varied -20.0 dB to -2.7 dB strike to
                                ; strike. Note that param 21 cannot itself provoke this, because this
                                ; clamp caps what reaches the DAC - so "raising cutoff does not ring"
                                ; does NOT exonerate high cutoff; it only shows the clamp works.
                                ; History: $E6 (90%) rang often; $D0 (82%) still rang occasionally on
                                ; fast chords (control-voltage transients from rapid DAC re-strobes).
                                ; Now 75% for more margin; raise by ear if the top end feels too dull.
; S83: the ceiling must FOLLOW RESONANCE. The self-oscillation threshold described above falls as Q
; rises, but CUTMAX was a fixed constant tuned at the default resonance of 20. Viz raised resonance
; to ~50 and the sporadic ringing returned: measured as large POSITIVE brightness spikes (+13.8 /
; +21.3 / +11.1 dB) mid-chord, pitch unchanged, at irregular spacing (4.29s / 2.11s) matching no
; refresh period - precisely the "some channels sporadically tip into oscillation, more likely with
; more notes held" behaviour this comment already predicted.
; Effective ceiling = CUTMAX - FRESV/8: resonance 0 keeps the full $C0, resonance 99 (FRESV = 253)
; pulls it to ~$A1. B holds the voice index and must survive, so it is saved around the arithmetic.
        PSHS  B                 ; voice index
        LDX   #FCEIL
        LDB   B,X               ; the calibrated ceiling for this unit
; S102: the S83 resonance slope is REMOVED. It pulled the ceiling DOWN as resonance rose, on the
; assumption that self-oscillation is always a fault. It is not - at high resonance it is a sound
; design tool, and Viz wants it available. FCAL calibrates the onset at LOW resonance, so a ceiling
; sitting just under that onset does the right thing at both ends by itself: at low Q the filter
; stays just below breaking into oscillation, and at high Q - where the threshold is lower - the
; same ceiling is above it, so the filter sings when asked to.
        PSHS  B                 ; effective ceiling
        CMPA  ,S
        BLS   FRWRCP1           ; at or below -> use as-is
        LDA   ,S                ; clamp down to the ceiling
FRWRCP1
        LEAS  1,S               ; drop the ceiling
        PULS  B                 ; restore voice index
FRWRCAP
; S207 (unified138): the stock-exact 4-store protocol, verbatim from ROM $F5E7 (see the re-audit):
;     STA $E418+ch   cutoff -> DAC, BOTH sections inhibited (preload: DAC settles disconnected)
;     STA $E410+ch   connect the cutoff cap to the settled DAC
;     STB $E418+ch   resonance -> DAC, disconnect everything (also ends the cutoff window cleanly)
;     STB $E408+ch   connect the resonance cap
; The LFCUT cache, the FRBUDG budget and the write-on-change skip are all GONE — every channel,
; every pass, like stock (32 writes/burst on stock is clean, so the count was never the buzz).
; A = clamped cutoff for this voice (0 for inactive voices, as before). B = voice index on entry.
        PSHS  B                 ; voice index
        LDX   #$E418
        ABX                     ; X = $E418 + voice
        LDB   RESVW             ; S210: THIS VOICE's resonance (base + vel/env/LFO, clamped)
        STA   ,X                ; preload cutoff (DAC loads, nothing connected)
        STA   -8,X              ; cutoff -> $E410+ch (cap samples a SETTLED DAC)
        STB   ,X                ; preload resonance (disconnects the cutoff cap at a clean value)
        STB   -16,X             ; resonance -> $E408+ch
        PULS  B                 ; restore voice index
FRWRSK
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        LBNE  FREF
; S207 PARK (stock $8A74: CLRA / STA -1,U -> $E41F := 0). DAC parked at ZERO, select latch left in
; the $E418 range = both CD4051 inhibits asserted. Nothing tracks the DAC between bursts, and the
; DAC rests at code 0 — the one thing every flat build had in common and every drifting build
; lacked. NOT the S202 park ($E417 = a live cutoff CONNECT on channel 7 — the opposite operation;
; it inverted the drift, S189). Skipped while armed: capture owns the filter then and parks $E417
; itself deliberately, to keep the input-filter CV pinned.
        LDA   SMPSTAT
        CMPA  #$01
        BEQ   FRNOPK
        CLRA                    ; pure write, no read-modify-write on the filter decode (CLR ext
        STA   $E41F             ; would issue a dummy READ cycle first; stock does CLRA/STA too)
FRNOPK

; --- blank the display once FREF's refresh cycle is done. Without this, the last segment written
;     (the mode dot at SEGCOL 7) is left holding $E20F through the whole non-FREF stretch of the pass
;     (TICKALL/KBSERV/PGSERV/next SYNCP..SMPSERV) = the dot glows far brighter than the digits. Both
;     anodes off ($18: bits3,4 set, active-low) = dark, matching what SEGREF already writes to bits 5-7.
;     Digits are unaffected (they were only ever lit during FREF); this just drops the dot to match.
        LDA   #$18
        STA   $E20F

; ---- envelope + LFO tick (timer-gated, like the proven synth) ----
        LDA   $E20D
        BITA  #$20
        BEQ   NOENV
        LDA   $E204
        JSR   ENVWRAP
; ---- value-display + keypad settle timers (once per env tick) ----
        TST   VTMR
        BEQ   ENVKP
        DEC   VTMR
; S148: the timer still runs out, but it NO LONGER FLIPS THE DISPLAY BACK TO PARAM MODE.
; Auto-revert meant that pausing while adjusting a value silently returned the display to parameter
; selection - so the next wheel movement changed WHICH PARAMETER was selected instead of its value,
; which is a genuinely destructive surprise while editing. The display now stays in VALUE mode until
; the player changes it deliberately; the param/value button still switches modes explicitly, and
; that path never used this timer.
ENVKP
        TST   KPTMR
        BEQ   NOENV
        DEC   KPTMR
NOENV

; ---- keyboard (drain ALL pending bytes this loop) ----
        JSR   KBSERV
        JSR   CC1SRV            ; S228b: apply the newest received CC1 (coalesced), once
        LBRA  MAIN              ; per pass - where the pager's JSR used to live

; ===== VLFOADV: advance voice LFO phase (call once per timer tick) =====
VLFOADV
        PSHS  A,B
        LDD   LFOINC            ; S229b: precomputed CURVED increment (see the SYNCP site):
                                ; 64p + (p*42>>6)*p - exactly the old speed at the floor,
                                ; exactly 2x at param 99, smooth in between. Replaces the
                                ; per-tick shift chain (this path runs 8 voices x 333 Hz;
                                ; the curve is computed once per param CHANGE instead).
        ADDD  OLFPHI,U
        STD   OLFPHI,U
        BCC   VLADONE           ; no phase wrap this tick
        JSR   RAND              ; new LFO cycle -> sample & hold a new random value (A = random)
        STA   OLFRND,U          ; latch into the voice struct (RAND preserves U)
VLADONE
        PULS  A,B
        RTS

; ===== LFOSC: A = param depth (0..99) -> LFOSCL = A*165>>6 (=255 at 99), clamped. =====
; Unified depth scaling so every LFO destination reaches its mathematical max at param 99.
; Clobbers A,B. Result in LFOSCL (and A).
LFOSC
        LDB   #165
        JSR   MSH6           ; S226R: MUL + >>6 shared. D = depth * 165 (max 99*165=16335, fits 16-bit) ; D >>= 6 ; B = result, A = high
        TSTA
        BEQ   LFOSCOK
        LDB   #$FF              ; clamp to 255
LFOSCOK
        STB   LFOSCL
        RTS

; ===== VLFOR: read voice phase -> signed scaled LFO offset in A (no advance) =====
; Waveform selected by LFOWAV (0=tri 1=saw+ 2=saw- 3=square). Scaled by LFOSCL (caller-set).
VLFOR
        PSHS  B
        LDA   LFOWAV
        BEQ   VWTRI             ; 0 = triangle
        CMPA  #$01
        BEQ   VWSAWUP           ; 1 = saw up
        CMPA  #$02
        BEQ   VWSAWDN           ; 2 = saw down
        CMPA  #$04
        BEQ   VWRAND            ; 4 = random sample & hold
; 3 = square: +127 for first half of phase, -127 for second half
        LDA   OLFPHI,U
        CMPA  #$80
        BCC   VWSQLO
        LDA   #$7F              ; +127
        BRA   VWSCALE
VWSQLO
        LDA   #$81              ; -127 (signed)
        BRA   VWSCALE
VWRAND
        LDA   OLFRND,U          ; per-voice S&H random (signed) via voice pointer; updated 1x/LFO cycle
; boost amplitude ~1.5x (saturating) so the S&H steps sit closer to the periodic waves' depth
        PSHS  A                 ; save original (sign)
        BPL   VWRAB
        NEGA                    ; A = |value|
VWRAB
        TFR   A,B
        LSRA                    ; A = |value|/2
        PSHS  B
        ADDA  ,S+               ; A = |value| + |value|/2 = 1.5*|value|
        CMPA  #$7F
        BLS   VWRAS
        LDA   #$7F              ; saturate to +127
VWRAS
        TST   ,S+               ; original sign
        BPL   VWRAP
        NEGA                    ; reapply negative sign
VWRAP
        BRA   VWSCALE
VWSAWUP
        LDA   OLFPHI,U          ; phase 0..255
        SUBA  #$80              ; signed ramp -128..127 (saw up)
        BRA   VWSCALE
VWSAWDN
        LDA   #$7F
        SUBA  OLFPHI,U          ; 127 - phase = saw down
        BRA   VWSCALE
VWTRI
        LDA   OLFPHI,U          ; phase hi
        CMPA  #$80
        BCS   VRR
        COMA                    ; S207/unified139: was NEGA. NEGA($80)=$80 (the -(-128) anomaly), so at
                                ; phase EXACTLY $80 the apex emitted -127 instead of +127: a full-scale
                                ; wrong cutoff for the 1-2 ticks the high byte sits on $80. Phase is
                                ; retriggered at note-on, so the tick/pass alignment is deterministic
                                ; per note - the same early apexes glitched on every key strike ("rough
                                ; jumps on the first two LFO cycles"; measured at 0.35s/0.97s = apexes
                                ; 1 and 2 exactly). COMA = 255-p: $80->+127, continuous through the
                                ; apex, and $FF->-127 still meets the rising half at the wrap.
VRR
        LSLA
        SUBA  #$7F              ; signed triangle -127..127
VWSCALE
; A = signed waveform value -127..127. Scale by LFOSCL.
        TFR   A,B
        TSTB
        BPL   VRP
        NEGB
        LDA   LFOSCL
        MUL
        TFR   A,B
        NEGB
        TFR   B,A
        PULS  B
        RTS
VRP
        LDA   LFOSCL
        MUL                     ; A = high byte
        PULS  B
        RTS

; ===== NOTE-ON =====
NOTEON
; --- same-key retrigger: first look for a voice ALREADY on this key (whether sounding or releasing).
;     If found, REUSE it - so retriggering a key restarts that same voice cleanly at the sample start,
;     instead of stacking a new voice on top of the old one's release tail (which would keep playing
;     the sample from where the released note left off). Only if no voice matches this key do we
;     allocate a fresh free voice below. ---
        LDU   #VBASE
        CLRB
NORETRG
        LDA   OACT,U
        BEQ   NORETRGN          ; inactive voice -> not a match
; S100: do NOT reuse a voice that is already RELEASING. Reuse restarts the envelope from zero and
; the sample from its start, so grabbing a voice whose release tail is still audible drops it
; instantly from its current level to silence - that is the click Viz hears when the same key is
; struck again with a long attack/release, even with only one note sounding. States 1-3 (attack,
; decay, sustain) still reuse, which is the correct behaviour for a key genuinely still held; state
; 4 is release and state 5 is the sustain-pedal hold, and both are left alone to finish.
        LDA   OAST,U
        CMPA  #$04
        BCC   NORETRGN          ; releasing or pedal-held -> leave it, take a free voice instead
        LDA   OKEY,U
        CMPA  KBKEY
        BEQ   NOGOT             ; same key already voiced -> reuse this voice (U,B point at it)
NORETRGN
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   NORETRG
; no existing voice on this key: find a FREE voice (OACT=0), else fall back to voice 0.
        LDU   #VBASE
        CLRB
NOFREE
        LDA   OACT,U
        BEQ   NOGOT
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   NOFREE
; S100: nothing free. Prefer a voice already in RELEASE over an arbitrary one - its tail is the
; quietest thing sounding and the least missed. Previously this fell back to voice 0 regardless,
; which could cut off a note in mid-attack while a nearly-silent release tail sat untouched.
        LDU   #VBASE
        CLRB
NOREL
        LDA   OAST,U
        CMPA  #$04
        BCC   NOGOT             ; in release (or pedal-held) -> take this one
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   NOREL
        LDU   #VBASE
        CLRB                    ; everything genuinely sounding -> voice 0, as before
NOGOT
        LDA   #$01
        STA   OACT,U
; --- S87: force this voice's filter CVs to be RE-DRIVEN for the new note. ---
; FREF is write-on-change, so a voice reusing the same cutoff value as its previous note produced NO
; write at all - the note simply played on whatever charge that channel's sample-and-hold happened to
; be holding, which depends on how long ago the rotation last topped it up. Different voices sit at
; different points in that cycle, so nominally identical chords came out at different brightnesses.
; Measured against the stock OS on the same unit, same figure: repeated-strike brightness sd was
; 1.43 dB for stock and 3.62 dB for us, while MID-NOTE noise was near-identical (1.77 vs 1.88 dB)
; and stock has -8 dB excursions of its own. So stock is not free of filter movement - it is
; CONSISTENT FROM STRIKE TO STRIKE, and that is precisely what a guaranteed re-drive at note-on buys.
; Invalidating the cache costs one DAC write per note, only when a note actually starts, and it is
; identical for every voice - no per-voice asymmetry (the trap that sank S75 and S85).
; B already holds the allocated voice index here - VIDX is not set until later - and the code below
; recomputes A from B, so only X needs preserving.
; S219: LFCUT/LFRES note-on invalidation DELETED - the caches have had no reader since the
; stock-exact refresh (S207-208: "the LFCUT cache... GONE - every channel, every pass").
        LDA   #$01              ; the value the original code left in A (load kept, now primary)
; --- PHASE RESET, per the official 5503 datasheet: "When M0 = 1 and H = 1, the oscillator's
;     accumulator will be reset to zero." The accumulator reset is a STATE (halted with the low mode
;     bit set), NOT a halt->run edge. Our previous halts wrote $01 (halt with M0=0, free-run), which
;     per the real chip never resets anything - the MAME model resets on any halt->run write edge,
;     which is more generous than silicon, and that mismatch is why every edge-based attempt failed on
;     hardware while looking fine in analysis. Deliberate presses only ever worked because the voice-
;     free path (HALTOSC) writes $07 = M0=1+H=1, resetting the accumulator when the release finished.
;     So: halt this voice's primary oscillator NOW with M0 SET (one-shot mode + halt = $03) - the
;     hardware resets its accumulator to zero. The RUN write at the end of note-on then starts playback
;     from the beginning. This works whether the oscillator was running (fast retrigger) or halted. ---
        PSHS  B                 ; preserve voice index
        TFR   B,A
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = channel<<4
        ORA   #$03              ; + one-shot mode (M0=1) + halt (H=1) -> ACCUMULATOR RESET in hardware
        ASLB                    ; B = 2V (primary oscillator index)
        LDX   #$ECA0
        STA   B,X               ; osc 2V: halted-with-M0 -> accumulator reset to zero
        PULS  B                 ; restore voice index
; invalidate the write-on-change caches for this voice, so the note's first volume and filter writes
; always reach the hardware (a fresh note must set its own level and cutoff, not inherit stale cached
; values). $FF sentinel guarantees the first compare differs and writes.
        LDX   #LVWR
        LDA   #$FF
        STA   B,X               ; volume cache sentinel
; S219: LFCUT/LFRES sentinels deleted here (no reader); LVWR above is KEPT (volume path still live).
        LDA   KBKEY
        STA   OKEY,U
        LDA   AGECTR
        STA   OAGE,U
        INC   AGECTR
        LDA   #$01
        STA   OAST,U
        CLR   OALV,U
        CLR   OALVL,U           ; clear amp accumulator low byte
        LDA   #$01
        STA   OFST,U
        LDA   FFLOORV
        STA   OFLV,U
        CLR   OFLVL,U           ; clear filter accumulator low byte
        LDA   #$01
        STA   OPST,U            ; pitch env -> attack
        CLR   OPLV,U            ; from level 0
; LFO trigger (param 63): 0 = retrigger (reset phase per note), 1 = free-run (leave phase running)
        TST   LFOTRG
        BNE   LFONORST          ; free-run -> skip phase reset
        CLR   OLFPHI,U
        CLR   OLFPLO,U
LFONORST
; velocity -> amp peak (vel*2 clamp) and filter peak (vel + $80 clamp, so harder=brighter)
; velocity -> amp peak, scaled by VAMPDEP (param 35).
;   velScaled = min(vel*2,255); deficit = 255-velScaled
;   reduction = (deficit * VAMPDEP) >> 7;  OAPK = 255 - reduction
;   VAMPDEP=0 -> OAPK=255 (constant level); VAMPDEP=99 -> OAPK ~= velScaled (full velocity).
;   reduction = min( (deficit*VAMPDEP) >> 6 , deficit ); OAPK = 255 - reduction.
;   The >>6 (vs >>7) and the clamp widen the range so velocity stays audible after the
;   analog compandor compresses dynamics.
;   All intermediate math via LFOTMP scratch (interrupt-safe, no stack-relative math).
;   B holds the voice index here and MUST survive (the freq calc below needs it) -
;   the MUL clobbers B, so stash the voice index in VIDX first and restore after.
        STB   VIDX              ; preserve voice index across the MUL
        LDA   KBVEL
        LSLA
        BCC   APKVS
        LDA   #$FF
APKVS
        STA   LFOTMP            ; LFOTMP = velScaled
        LDA   #$FF
        SUBA  LFOTMP            ; A = deficit (255 - velScaled)
        STA   VADEF             ; VADEF = deficit
        LDB   VAMPDEP
        JSR   MSH6           ; S226R: MUL + >>6 shared. D = deficit * VAMPDEP (clobbers B) ; D >>= 6 ; B = reduction (low), A = high (~0)
        TSTA
        BNE   VACLAMP           ; reduction > 255 -> clamp to deficit
        CMPB  VADEF
        BLS   VARED             ; reduction <= deficit -> keep
VACLAMP
        LDB   VADEF             ; clamp reduction to deficit
VARED
        STB   LFOTMP            ; LFOTMP = reduction
        LDA   #$FF
        SUBA  LFOTMP            ; A = 255 - reduction = OAPK
        STA   OAPK,U
        LDB   VIDX              ; restore voice index for the rest of NOTEON
; filter peak: brighter with velocity. fpk = $80 + (vel>>1) -> range $80..$FF
        LDA   KBVEL
        LSRA
        ADDA  #$80
        BCC   FPKOK
        LDA   #$FF
FPKOK
        STA   OFPK,U
; pitch -> swap pair (osc 2V transient + osc 2V+1 loop, both channel V).
; B = voice index. Look up freq word, write to BOTH oscillators of the pair.
; SWAP MODE (mode bits 11 = $06): transient 2V plays the wave once then hands off to
; partner 2V+1, which plays once then hands back. Only ONE oscillator sounds at a time
; (sequential), matching the stock OS - never two simultaneously into one channel S&H.
        LDA   KBKEY
        ADDA  #$0E              ; key->freqtab index offset (real-kbd middle C = idx36)
        ADDA  TUNEOFS           ; + signed base-note/coarse-tune semitone offset
        ADDA  TRANSPOSE         ; + octave transpose (Sample Upper/Lower)
        ANDA  #$7F
        ASLA
        STB   VIDX              ; voice index -> scratch (no stack juggling through math)
        TFR   A,B
        LDX   #$9600
        ABX                     ; X -> freq table entry (lo at ,X / hi at 1,X)
; ---- apply fine tune: FREQADJ = freqword +/- delta, delta = (freq>>6)*|fine| >> 5 ----
; FREQADJ stored LO-first (,X=lo, 1,X=hi). B is fully free (voice index is in VIDX).
        JSR   FINEAPP           ; S153: base word + fine tune (shared with VIBGO)
        STB   FREQADJ           ; adjusted lo  (lo-first)
FINEDONE
; ---- SAMPLE-MODE rate scaling ----
; The freqtab is tuned for the single-cycle SYNTH wave (loops the 32768-sample buffer at the note
; pitch). A recorded sample played that fast collapses into a tone. When a sample has been recorded
; (SMPRDY set), shift the frequency word right by SMPSHFT (set from the capture rate) so the buffer
; plays at its natural recorded rate at the base note, transposed by the keyboard. The shift tracks
; the sample rate so any rate plays back at unity pitch.
; S234b: the guard moved into SCALEW, which also trims the boot sawtooth (see SCALEW).
; Divide the note frequency by 2^SMPSHFT (S49: was hardcoded >>3). With playback RESOLUTION 7
; (freq/512 in-chip), rate 1 (shift 3) gives the proven /4096 total; faster rates shift less so any
; capture rate plays at unity pitch. SMPSHFT comes from SMPSHTAB at capture (or the slot header on
; load) and is clamped to 0-7 here, so corrupt state can only mistune, never hang.
        JSR   SCALEW            ; S234b: sample -> SMPSCALE; boot saw -> SAWK trim. (S226R:
;                                 the PSHS/PULS B around the old copy was vestigial - B is
;                                 reloaded from FREQADJ inside and from VIDX by every caller after)
FREQWR
        JSR   FWRPAIR           ; write FREQADJ to both oscillators of voice VIDX
        JSR   DTSET             ; detune: set up (or halt) osc 16+V from FREQADJ, DAMT, MIX
        LDB   VIDX              ; B = voice index (restored for the control writes below)
        ASLB                    ; B = 2V (primary/transient oscillator index)
; PAGED PLAYBACK: with a real sample loaded, prime the oscillator PAIR for 512-byte swap-mode paging
; (this is what makes fine sample start work). Without a sample (the boot synth wave), fall through to
; the original single-oscillator free-run path below, which is unchanged.
; S64: the S63 "route one-shot notes to free-run with a 32K table" experiment is REVERTED. It was
; built on the claim that output frequency depends only on RESOLUTION. It does not: es5503.cpp:192
;   resshift = resshifts[resolution] - wavetblsize
; so the SIZE field is part of the rate arithmetic. Switching size 512 -> 32K while keeping the
; paged resolution shortened the shift by 6 -> the address advanced 64x too fast -> decimation
; aliasing (hardware-measured: played pitches 2.2-5.5kHz regardless of key, inharmonic energy at or
; above harmonic). The same arithmetic is what makes S54's res+1 = one octave down work, and what
; broke S49's shift-based rate scaling. For the record, a CORRECT free-run 32K config exists:
; resshift 9 needs resolution 7 at size 7 - exact for a rate-2 sample, and rate 1 would additionally
; need the frequency word halved (shift 4), which costs one bit of the word envelope.
; S68: route ONE-SHOT notes at resshift-9 rates (2 and 3) to the free-run path with the whole 32K
; buffer as a single wavetable - no paging, hence no page-boundary phase discontinuity. Evidence:
; the metallic inharmonicity is present at every rate and gets WORSE with rate (Viz: rate 3 has more
; beating than rate 1), and page swaps per second scale exactly the same way (6.1 / 11.3 / 20.8 at
; rates 1/2/3). Each swap restarts the incoming oscillator's accumulator at 0 (es5503.cpp halt_osc),
; so up to a full sample of phase is lost per page -> phase modulation at the swap rate -> sidebands
; a few Hz either side of every harmonic. Stock plays free-run over the full table and is clean.
; CONFIG (verified against es5503.cpp:192, resshift = (9+res) - size): $3F = size 7 (32K) + res 7 ->
; resshift 9, IDENTICAL to the paged $09 of rates 2 and 3, so pitch and the param 6/13 values are
; unchanged. This is S63's idea with the arithmetic done right: S63 used $3A (res 2 at size 7) =
; resshift 4, which played 64x too fast and produced the decimation hash.
; Rate 1 needs resshift 10, unreachable at size 7 (res maxes at 7), so it stays paged for now -
; deliberately, to keep this to one variable. Loops and fine sample starts also stay paged: free-run
; has no loop points and its wavetable pointer cannot offset into a 32K-aligned table.
        CLR   R1PAIR            ; S228b: default = not the rate-1 pair (set only in NPR1)
        LDA   SMPRDY
        LBEQ  NPFREE            ; no sample -> boot-wave free-run below (S224 pushed this out of
                                ; short-branch range; long branch, +1 byte)
; S227: THE PAGER HAS NO USERS LEFT. Fine sample start rides the same data rotation as loop
; start (SYNCP rotates the buffer so the note's start point sits at offset 0), and rate-1
; one-shots free-run with a halved frequency word (SMPSCALE). Every sample note is routed
; below: loop -> sized-table swap-pair engine, one-shot -> free-run + end marker.
        LDA   LMODE
        BEQ   NPFRC0            ; one-shot -> free-run, every rate (S227)
; ===== S222: LOOPED NOTES LEAVE THE PAGER =====
; The S218 reroute was reverted on the grounds that free-run trades the S215 tick for the
; accumulator amplitude ramp. That was the wrong call, and S221 proved it two ways.
;  (1) MECHANISM, from es5503.cpp's halt handler. On a FREE-RUN wrap the accumulator is not
;      zeroed, it is DECREMENTED by the table span - "preserve the relative phase of the
;      oscillator when looping". The SWAP branch instead does partner->accumulator = 0, with
;      MAME's own comment "does this also need phase preservation?" attached to it. That
;      discarded sub-sample IS the tick: one phase step per swap, measured at exactly the
;      swap rate on three builds and two page sizes (S220b table).
;  (2) REFERENCE, from the stock OS. A 32K stock wavesample looped has NO swap comb at all -
;      every peak in its phase-modulation spectrum is a harmonic of the loop PASS rate. And
;      the amplitude ramp we refused the trade over is present in stock too, at the same
;      order (14.7% depth vs its own 12.3% loop-off control; ours 9.3% vs 7.8%). Stock ships
;      the ramp and does not ship the tick.
; This build takes only the narrow case, one variable: the loop IS the whole 32K table, so it
; is the free-run one-shot path we already trust with the ending removed. Loop start elsewhere
; needs a smaller table plus a data rotate to align it (stock's param 66 exists for exactly
; that) - S223. Rate 1 needs resshift 10, which caps the table at size 6 = 16384 bytes, so a
; full-buffer rate-1 loop cannot be a single table and keeps paging.
; ===== S223: SIZE THE TABLE TO THE LOOP, NOT TO THE BUFFER =====
; S222b shipped only the whole-32K loop, which meant a SHORT capture looped through
; 32K of whatever preceded it. The DOC can wrap any of its eight table sizes, so pick
; the largest power-of-two page count that fits the loop and wrap THAT instead.
;   size field s -> table = 256<<s bytes;  resshift = (9+res) - s
;   resshift 9  (rates 2-3): res = s,   so s can reach 7 = 32768 bytes
;   resshift 10 (rate 1):    res = s+1, and res maxes at 7, so s stops at 6 = 16384
; The second line is why rate 1 could not free-run the whole buffer and had to keep
; paging - it joins the clean engine here for every loop of 16K or less, which is most
; of them, since rate 1 is the long-sample rate.
; The table base is 0, which is aligned for every size, so nothing has to move. The
; cost is that the loop LENGTH snaps down to a power of two - the only lengths this
; chip can wrap. Arbitrary loop START still needs the data rotated (stock's param 66
; exists for exactly that) and stays on the pager until S224.
        PSHS  B                 ; [S] = 2V - B is the oscillator index for the whole routine
        LDA   ENDPG             ; S224: pages-1, i.e. the last page inside the loop
        CLRB
LPSZLP  LSRA
        BEQ   LPSZD
        INCB
        BRA   LPSZLP
LPSZD   ADDB  #$02              ; S224: SMALLEST table that CONTAINS the loop end, not the
                                ; largest that fits inside it - the sentinel has to be reachable.
                                ; ENDPG 0-1 -> 1024, 2-3 -> 2048 ... 16-31 -> 16384, 32-63 -> 32768.
        CMPB  #$07
        BLS   LPSZ1
        LDB   #$07
LPSZ1   LDA   SMPRES
        CMPA  #$0A
        BEQ   LPSZR1            ; rate 1 -> resshift 10
        TFR   B,A               ; every other rate -> resshift 9 (S227: the pager fallback
                                ; is gone; an unknown SMPRES is treated as $09, defensive)
        ASLA
        ASLA
        ASLA                    ; A = size<<3
        PSHS  B
        ADDA  ,S+               ; A = (size<<3)|size  -> res = size, resshift 9
        LDB   SMPRES            ; (B is free: LPSZW reloads it)
        CMPB  #$08
        BNE   LPSZW
        DECA                    ; S233b rate 4: res = size-1 -> resshift 8 (size >= 2, so res >= 1)
        BRA   LPSZW
LPSZR1  CMPB  #$06
        BLS   LPSZR2
        LDB   #$06              ; rate 1 tops out at a 16K table
LPSZR2  TFR   B,A
        ASLA
        ASLA
        ASLA
        PSHS  B
        ADDA  ,S+
        INCA                    ; A = (size<<3)|(size+1) -> res = size+1, resshift 10
LPSZW   PULS  B                 ; B = 2V again
        LDX   #$ECC0
        STA   B,X               ; osc 2V: table sized to hold the loop
        LEAX  B,X
        STA   $01,X             ; osc 2V+1: the same table (it is the swap partner below)
        LDX   #$EC80
        CLR   B,X               ; osc 2V wavetable pointer = 0 (aligned for every size)
        LEAX  B,X
        CLR   $01,X             ; osc 2V+1 the same - both play the identical loop
        LDA   ENDPG
        CMPA  #63
        LBEQ  NPFREE            ; FULL loop -> single oscillator, FREE-RUN, hardware wrap.
                                ; That wrap PRESERVES phase (es5503.cpp: accumulator -=
                                ; wtsize<<resshift) and involves no handoff at all, so it
                                ; stays exactly the path 156-159 proved. Nothing to beat.
; ===== S225: SWAP-PAIR LOOP SEAM - THE GAP GOES AWAY =====
; 159 loops correctly but pays a 12-13 ms silent hole at every seam: the sentinel halts
; the oscillator and it sits halted until PGSERV next runs, once per main-loop pass.
; Measured on Viz's recording - 12-28 ms wide, 42-52 dB deep. Servicing faster only
; shrinks the hole; it cannot remove it, because the CPU is in the loop at all.
; SWAP MODE takes the CPU out of it entirely. The pair share one table, one wavetable
; pointer and one frequency word. The running oscillator reaches the $00 sentinel at the
; loop end, halts, and THE DOC ITSELF starts the partner with its accumulator zeroed -
; in hardware, within one scan, no service and no gap. The partner then runs the same
; loop and hands back. It ping-pongs forever with zero CPU involvement.
; This is what swap mode is FOR - the Ensoniq documentation describes exactly this use,
; "dividing a waveform into an attack part played once and a looped sustain part without
; additional CPU overhead". S215's tick came from using swap per 512-byte PAGE, ~18
; handoffs a second. One handoff per LOOP PASS costs the same sub-sample phase step
; once every few seconds, which is a seam click at worst - not a 13 ms dropout.
; The halted partner sits at M0=1 & H=1 (swap is mode 11), so the S216 level condition
; holds its accumulator at zero for us: it always resumes at the head of the loop.
        LDA   VIDX
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = channel<<4
        LDX   #$ECA0
        LEAX  B,X               ; X = $ECA0 + 2V
        PSHS  A
        ORA   #$07              ; osc 2V+1: swap + halted, waiting with a zeroed accumulator
        STA   $01,X
        PULS  A
        ORA   #$06              ; osc 2V: swap + running, plays the loop from byte 0
        STA   ,X
        LDB   VIDX              ; restore the voice index for the caller
        RTS
NPFRC0
; S228b: rate-1 one-shots at FULL PRECISION. The S227 halved-word trick truncated the
; word BEFORE the tune multiply: -12c at middle C, key-dependent (Viz measured -15c;
; loop-on at the same rate was exact, proving k=97 right and the halving wrong).
; resshift 10 caps a table at 16K, so the 32K sample is TWO 16K tables: osc 2V (SWAP,
; base 0) plays the first half, and the DOC hands off - accumulator zeroed in hardware,
; the proven S225 seam - to osc 2V+1 (ONE-SHOT, base $4000), which plays the second half
; and halts at the end marker or table end. One-shot mode on the partner means NO
; hand-back (the S150 replay trap). If the sample END sits in the first half
; (SENDPOS < $40), osc 2V runs plain one-shot on its 16K table instead - it halts at the
; marker and the partner is never started.
        LDA   SMPRES
        CMPA  #$0A
        BEQ   NPR1              ; rate 1 -> the 16K pair below
        LDA   SMPRES            ; S233b: $09 (rates 2-3) -> $3F = 32K res 7 resshift 9;
        ANDA  #$01              ;        $08 (rate 4)    -> $3E = 32K res 6 resshift 8.
        ADDA  #$3E              ; ($0A took NPR1 above; only $08/$09 reach here)
        LDX   #$ECC0
        STA   B,X
        LDX   #$EC80
        CLR   B,X               ; wavetable pointer = page 0 (the sample lives at $0000-$7FFF)
        BRA   NPR1D
NPR1
        LDX   #$ECC0
        LDA   #$37              ; 16K table (s=6), res 7 -> resshift 10: TRUE rate-1 domain
        STA   B,X               ; osc 2V
        LEAX  B,X
        STA   $01,X             ; osc 2V+1: same domain
        LDX   #$EC80
        CLR   B,X               ; osc 2V wtptr = 0 (first half)
        LEAX  B,X
        LDA   #$40
        STA   $01,X             ; osc 2V+1 wtptr = $4000 (second half, 16K-aligned)
        LDA   SENDPOS
        BEQ   NPR1P             ; no marker -> the note runs the whole 32K -> pair
        CMPA  #$40
        BCS   NPR1D             ; marker in the first 16K -> single-osc one-shot suffices
NPR1P
        LDA   #$01
        STA   R1PAIR            ; control writes below: 2V = swap, 2V+1 = one-shot+halted
NPR1D
NPFREE
; --- (no sample loaded, or one-shot free-run: original single-oscillator path) ---
; --- sample start: NOTE - the DOC wavetable pointer is a PAGE number, and with a 32K wavetable only
;     bit 7 of the pointer is used (page must be aligned to the wavetable size, per the 5503
;     datasheet). So the pointer cannot start partway into our 32KB sample - any sub-32K value is
;     masked to page 0. Fine sample-start therefore CANNOT be done with the pointer here; it needs the
;     sample DATA shifted so the start lands at offset 0 (handled separately). We leave wtptr at 0.
; --- control: channel = voice index, FREE-RUN mode ($00) ---
; Free-run loops a SINGLE oscillator cleanly: no swap handoff. Swap mode caused two problems we now
; avoid: (1) the documented centerline glitch at each handoff = buzz, and (2) a second oscillator of
; the pair reading the buffer at a different rate = a steady tone mixed under the sample (the 110Hz
; tone). Free-run halts on $00 sample bytes, but the capture substitutes every $00 -> $01 across the
; FULL buffer (and the boot wave has no $00), so nothing halts. The partner oscillator stays halted.
        LDA   VIDX              ; A = voice index (channel) from scratch
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = channel<<4
; --- loop: in loop mode, enable this oscillator's halt interrupt (control bit $08). When it reaches
;     the 0x00 sentinel at loop-end it halts AND raises an IRQ; the main loop (LOOPSRV) sees the flag
;     via $ECE0 and restarts the oscillator at loop-start. In one-shot mode we leave the IRQ off so it
;     simply halts at the sample-end sentinel. Only relevant with a real sample loaded. ---
        PSHS  A                 ; save channel<<4
        LDA   SMPRDY
        BEQ   FRQCTL            ; no sample: the boot wave stays FREE-RUN - it is meant to loop
; S69: a SAMPLE reaching here is always one-shot (the FREQWR routing sends looped samples, fine
; sample starts and rate 1 to the paged engine), so select ONE-SHOT MODE. This was the u27 bug:
; free-run mode halts only on a $00 data byte (es5503.cpp:123, "mode != MODE_FREE || type != 0"),
; and capture scrubs every $00 to $01 across the whole buffer - so nothing could ever stop the note
; and every key looped forever regardless of param 14. One-shot halts at the end of the wavetable
; AND on a zero byte, so the note now ends at the 8-zero end marker if one is set, otherwise at the
; end of the 32K buffer. The partner oscillator below inherits the same mode bits while halted.
        LDA   LMODE
        BNE   FRQCTL            ; S222: a LOOPED sample stays in FREE-RUN mode - the table wraps
                                ; forever, phase preserved, no swap and no CPU service. Safe to
                                ; leave running because free-run only halts on a $00 data byte:
                                ; capture scrubs every $00 to $01 across the whole buffer, and
                                ; loop mode guarantees the end marker is REMOVED from the buffer
                                ; rather than merely ignored (S126). Both preconditions already
                                ; hold; neither is new to this build.
        TST   R1PAIR
        BEQ   NPOS1
        LDA   ,S
        ORA   #$06              ; S228b: rate-1 pair -> osc 2V in SWAP mode so the DOC
        STA   ,S                ; hands off to the $4000 half; partner forced one-shot
        BRA   FRQCTL            ; in FRQCTL below
NPOS1
        LDA   ,S
        ORA   #$02              ; mode bits 2-1 = 01 = one-shot
        STA   ,S
FRQCTL
        LDA   ,S+               ; A = control base (channel<<4, +$08 if looping); drop the saved copy
; --- KEY-ON PHASE RESET: the DOC only resets an oscillator's phase accumulator to the start of the
;     wavetable when its control register transitions from HALTED (bit0=1) to RUNNING (bit0=0). In
;     free-run mode the oscillator keeps looping after note-off, so if we just write "running" again
;     the accumulator is NOT reset and the sample starts from wherever it happened to be (the phase
;     drift heard between notes). So we first write HALTED, then RUNNING - that halt->run edge makes
;     the DOC zero the accumulator, so every note starts cleanly at the head of the buffer. ---
        PSHS  A                 ; [S] = control base (free-run bits 00, +$08 if looping)
; The oscillator was already HALTED at the very start of note-on (see EARLY HALT above), and all the
; note setup since then is far longer than one DOC scan - so the scan has latched the halted state.
; We now write RUNNING once, which the scan sees as a clean halt->run edge and zeroes the phase. We do
; NOT write HALT here (a back-to-back HALT+RUN would recreate the scan race that broke fast retriggers).
        LDA   ,S                ; A = control base (halt bit clear = running)
        LDX   #$ECA0
        STA   B,X               ; osc 2V: RUNNING, free-run - halt->run edge resets phase to buffer start
; partner osc 2V+1: halted (unused in free-run mode)
        INCB                    ; B = 2V+1
        PULS  A                 ; A = control byte (channel<<4 | loop bits)
        ORA   #$01              ; set halt bit: partner stays halted
        TST   R1PAIR
        BEQ   FRQP1
        ANDA  #$FB              ; S228b: rate-1 pair partner = ONE-SHOT+halted ($03), not
                                ; swap+halted ($07): started by 2V's swap regardless (the
                                ; hand-off is the HALTING osc's property), then halts DEAD
                                ; at the marker - no hand-back, no replay. M0=1 & H=1
                                ; while waiting, so the level condition holds its
                                ; accumulator at zero: it starts exactly at $4000.
FRQP1
        STA   B,X               ; osc 2V+1: halted, channel V
        DECB                    ; B = 2V
        LSRB                    ; B = V (restore voice index for caller)
        RTS

; ===== S227b: THE PAGER IS GONE =====
; NOPAGE + PGSERV (the 512-byte paged playback engine, S13->S225) lived here, ~230 bytes.
; Build 166 removed its last users (fine start and rate-1 one-shots ride the S226 buffer
; rotation / halved-word free-run) and hardware-verified the rerouting with the pager still
; present but unreachable; this build deletes the body. The assembler itself proves no
; caller remains (any surviving reference to NOPAGE/PGSERV/PGLOAD/... would be an undefined
; label). Freed RAM: VNEXTP (8B), PGOSC, PGVOICE. The S215 tick law and the whole pager
; forensics remain in claude_TECH_FINDINGS_OROVELA / the reaudit log - do not rebuild one.

; ===== NOTE-OFF =====
NOTEOFF
        LDU   #VBASE
        CLRB
NOFF
        LDA   OACT,U
        BEQ   NOFFN
        LDA   OAST,U
        CMPA  #$04              ; already releasing? skip
        BEQ   NOFFN
        LDA   OKEY,U
        CMPA  KBKEY
        BNE   NOFFN
; S89: with the pedal down, park the envelopes in state $05 instead of $04. The tick dispatchers
; decode states 1-4 and fall through to RTS on anything else, so state 5 simply HOLDS the current
; level - sustain, with no extra per-voice storage (the 16-byte voice struct is full).
        LDA   #$04
        TST   SUSTAIN
        BEQ   NOFFREL
        LDA   #$05              ; pedal down -> hold, release when it lifts
NOFFREL
        STA   OAST,U            ; amp
        STA   OFST,U            ; filter
        STA   OPST,U            ; pitch env
NOFFN
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   NOFF              ; continue: release ALL matching voices
        RTS

; ===== TICKALL =====
TICKALL
        LDU   #VBASE
        CLRB
TVLOOP
        LDA   OACT,U
        BEQ   TVNEXT
        JSR   AMPTICK
        JSR   FILTTICK
        JSR   VLFOADV
        JSR   DRIFTUPD          ; slow random drift of the detune amount (no-op when DRAND=0)
        JSR   PITTICK           ; pitch env: advance OPLV
        JSR   VIBR              ; LFO + pitch-env -> rewrite freq
TVNEXT
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   TVLOOP
        RTS

; AMP env (peak = OAPK, sustain = 3/4 OAPK)
AMPTICK
        LDA   OAST,U
        LBEQ  AEND
        CMPA  #$01
        BEQ   AATK1
        CMPA  #$02
        BEQ   ADEC1
        CMPA  #$03
        BEQ   ASUS1
        CMPA  #$04
        BEQ   AREL1
        RTS
AATK1
; 16-bit: {OALV:OALVL} += AATKV, saturate at {OAPK:00}
        PSHS  B
        LDD   OALV,U
        ADDD  AATKV
        BCS   AATKSAT           ; overflow past $FFFF -> saturate to peak
        CMPA  OAPK,U
        BCC   AATKSAT           ; hi >= peak -> reached peak
        STD   OALV,U
        PULS  B
        LBRA  AWRV
AATKSAT
        LDA   OAPK,U
        STA   OALV,U
        CLR   OALVL,U
        LDA   #$02
        STA   OAST,U
        PULS  B
        LBRA  AWRV
ADEC1
; 16-bit: {OALV:OALVL} -= ADECV, floor at {sustain_target:00}
        JSR   ASUSTGT           ; A = sustain target hi byte (peak*ASUSV>>8), B preserved
        PSHS  B
        PSHS  A                 ; sustain target hi on stack (under saved B)
        LDD   OALV,U
        SUBD  ADECV
        BCS   ADECHIT           ; underflowed past 0 -> hit target
        CMPA  ,S                ; compare hi byte to sustain target
        BLS   ADECHIT
        STD   OALV,U
        PULS  A                 ; discard target
        PULS  B
        LBRA  AWRV
ADECHIT
        PULS  A                 ; A = sustain target hi
        STA   OALV,U
        CLR   OALVL,U
        PULS  B
        TSTA                    ; sustain target 0? voice silent
        BEQ   ADECFREE
        LDA   #$03
        STA   OAST,U
        LBRA  AWRV
ADECFREE
        CLR   OALV,U
        CLR   OALVL,U
        CLR   OAST,U
        CLR   OACT,U            ; free the silent voice
        JSR   HALTOSC           ; stop both oscillators + zero both volumes (B preserved)
        RTS
ASUS1
        JSR   ASUSTGT           ; A = sustain target hi, B preserved
        STA   OALV,U
        CLR   OALVL,U
        LBRA  AWRV
AREL1
; exponential release: step16 = (OALV_hi * RELK) + floor; graceful taper to 0.
        PSHS  B                 ; save voice index
        LDA   OALV,U            ; level high byte
        LDB   ARELV+1           ; RELK coefficient
        MUL                     ; D = OALV_hi * RELK
        ADDD  #$0040            ; + floor (ensures reaches 0)
        TFR   D,X               ; X = step16
        LDD   OALV,U            ; D = {OALV:OALVL}
        PSHS  X
        SUBD  ,S++              ; D -= step16
        BCS   ARELDONE          ; underflow -> done
        TSTA
        BEQ   ARELDONE          ; hi reached 0
        STD   OALV,U
        PULS  B
        LBRA  AWRV
ARELDONE
        PULS  B
ARELM
        CLR   OALV,U
        CLR   OALVL,U
        CLR   OAST,U
        CLR   OACT,U
        JSR   HALTOSC           ; stop both oscillators + zero both volumes (B preserved)
        RTS

; HALTOSC: halt BOTH oscillators of voice B's swap pair (2B, 2B+1) and zero both
; volumes. control = (channel<<4) | $07 (swap mode + halt). Preserves B (voice index).
HALTOSC
        PSHS  B                 ; save voice index
; control byte = (voice<<4) | $07  (channel=voice, swap mode, halt)
        TFR   B,A
        ASLA
        ASLA
        ASLA
        ASLA
        ORA   #$07
        PSHS  A                 ; [S] = control byte ; [S+1] = voice index
        ASLB                    ; B = 2V (first oscillator of pair)
; --- osc 2V ---
        LDX   #$ECA0
        STA   B,X               ; control: swap mode + halt
        LDX   #$EC40
        CLR   B,X               ; vol = 0
; --- osc 2V+1 ---
        INCB
        LDX   #$ECA0
        STA   B,X
        LDX   #$EC40
        CLR   B,X
; --- detune osc 16+V ---
        LDB   1,S               ; voice index (under the saved control byte)
        ADDB  #$10              ; B = 16+V
        LDA   ,S                ; saved control (V<<4)|$07
        ANDA  #$F0              ; keep channel bits
        ORA   #$03              ; halt + M0
        LDX   #$ECA0
        STA   B,X               ; halt detune osc
        LDX   #$EC40
        CLR   B,X               ; vol = 0
        PULS  A                 ; discard control byte
        PULS  B                 ; B = voice index (restored)
        RTS
; AWRV: write amp level OALV to BOTH oscillators of voice B's swap pair (2B, 2B+1).
; Only one sounds at a time (swap), but both must carry the level so the handoff is
; seamless. Preserves nothing critical; returns to caller. B = voice index on entry.
AWRV
        LDA   OALV,U            ; base amp level
; ---- LFO -> amplitude: add scaled LFO offset (depth = LFOADEP, param 64) ----
        STA   VADEF             ; VADEF = base amp level
        LDA   LFOADEP
        BEQ   AWNOLFO           ; amp LFO depth 0 -> no modulation
        STB   VIDX              ; preserve voice index across LFOSC (uses MUL)
        JSR   LFOSC             ; LFOSCL = LFOADEP scaled (255 at param 99)
        LDB   VIDX              ; restore voice index
        JSR   VLFOR             ; A = signed LFO offset (scaled)
        PSHS  B                 ; save voice index across the add
        TFR   A,B
        SEX                     ; D = sign-extended LFO offset
        ADDB  VADEF
        ADCA  #$00              ; D = base + LFO (signed 16-bit)
; clamp to 0..255
        TSTA
        BMI   AWZERO            ; negative -> 0
        BNE   AWMAX             ; >255 -> 255
        TFR   B,A
        BRA   AWCLMPD
AWZERO
        CLRA
        BRA   AWCLMPD
AWMAX
        LDA   #$FF
AWCLMPD
        PULS  B                 ; restore voice index
        BRA   AWWRITE
AWNOLFO
        LDA   VADEF             ; no LFO: use base level
AWWRITE
; --- write-on-change: cache the (pre-mix) envelope level; only recompute/write the DOC volumes when
;     it changes (steady sustain skips the writes, avoiding the 333Hz re-strobe buzz). A = env level,
;     B = voice. Primary gets env*MIXP>>7, detune osc gets env*MIXD>>7 (MIXP+MIXD=128 = constant-sum
;     crossfade, so blending detune in doesn't just add loudness). ---
        PSHS  B                 ; [S] = voice index
        LDX   #LVWR
        CMPA  B,X               ; env level unchanged since last write?
        BEQ   AWSKIP
        STA   B,X               ; cache env level
        PSHS  A                 ; [S]=env, [S+1]=voice
; S118: while ARMED, force the level to zero HERE rather than zeroing the registers elsewhere.
; S117 cleared the volume registers from the main loop, but AMPTICK writes them from the tick
; handler at ~307Hz against the main loop's ~111Hz - so the volumes were restored between passes and
; the two writers chopped against each other, which is the "bit-reduced" sound Viz heard, and the
; voices stayed audible in the level reading. Gating the single place the level is computed stops it
; at the source: nothing else writes a non-zero voice volume.
        LDA   SMPSTAT
        CMPA  #$01
        BNE   AWNOTARM
        CLRA
        STA   ,S                ; env level 0 -> both the primary and detune volumes come out 0
AWNOTARM
        LDA   ,S
        LDB   MIXP
        MUL                     ; A=env * MIXP -> D
        ASLB
        ROLA                    ; A = (env*MIXP)>>7 = primary volume
        LDB   1,S               ; voice
        ASLB                    ; B = 2V
        LDX   #$EC40
        STA   B,X               ; vol osc 2V
        INCB                    ; B = 2V+1
        STA   B,X               ; vol osc 2V+1
        LDA   ,S                ; env level
        LDB   MIXD
        MUL                     ; A=env * MIXD -> D
        ASLB
        ROLA                    ; A = (env*MIXD)>>7 = detune volume
        LDB   1,S               ; voice
        ADDB  #$10              ; B = 16+V (detune osc)
        STA   B,X               ; vol osc 16+V  (X still $EC40)
        PULS  A                 ; discard saved env
AWSKIP
        PULS  B                 ; restore voice index
AEND
        RTS

; ===== VIBR: LFO -> pitch (vibrato). Rewrites this voice's freq with the LFO offset. =====
; Input: U = voice ptr, B = voice index. Called per active voice each tick from TICKALL.
; If LFOPDEP=0, does nothing (note-on's freq stands). Else recomputes base freq from OKEY,
; adds scaled LFO offset, writes both oscillators of the swap pair.
; All math via scratch (FREQADJ/VIBTMP), no stack-relative ops (interrupt-safe).
VIBR
        LDA   LFOPDEP
        BNE   VIBGO             ; vibrato active
        LDA   PDEP
        BNE   VIBGO
        LDA   PBACT             ; S89: pitch bend needs the frequency rewritten too
        LBEQ  VIBEND            ; nothing modulating at all -> note-on freq stands
VIBGO
        STB   VIDX              ; preserve voice index (MUL/ABX clobber B)
; --- recompute base freq from OKEY (same mapping as NOTEON) ---
        LDA   OKEY,U
        ADDA  #$0E
        ADDA  TUNEOFS
        ADDA  TRANSPOSE
        ANDA  #$7F
        ASLA
        TFR   A,B
        LDX   #$9600
        ABX                     ; X -> freqtab entry (lo at ,X, hi at 1,X)
        JSR   FINEAPP           ; S153: base word + FINE TUNE. This path previously reloaded the
;                                raw table entry every pass and discarded the fine adjustment.
; --- vibrato (LFO -> pitch), only if LFOPDEP>0 ---
        LDA   LFOPDEP
        BEQ   VIBNOV            ; no vibrato -> skip to pitch env
        JSR   LFOSC             ; LFOSCL = LFOPDEP scaled (255 at param 99)
        LDB   VIDX              ; restore voice idx (VLFOR preserves U, uses B internally)
        JSR   VLFOR             ; A = signed LFO offset (small, scaled by depth)
; scale the LFO offset by (base freq >> 6) so vibrato depth tracks pitch (musical).
; delta = LFOoffset * (freq>>6) >> 4  (signed). Magnitude approach via scratch.
        STA   VIBTMP            ; VIBTMP = signed LFO offset
        JSR   FSH6            ; S226R: FREQADJ>>6 shared. D = freq>>6 ; B = t (low), A ~0
        LDA   VIBTMP
        BPL   VIBPOS
        NEGA                    ; A = |LFO offset|
VIBPOS
        MUL                     ; D = t * |offset|
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D = delta magnitude = (t*|offset|)>>4
        STD   VIBDLT            ; stash delta (16-bit)
        LDA   VIBTMP
        BMI   VIBSUB
; positive: freq + delta
        LDA   FREQADJ+1
        LDB   FREQADJ
        ADDD  VIBDLT
        BRA   VIBWR
VIBSUB
        LDA   FREQADJ+1
        LDB   FREQADJ
        SUBD  VIBDLT
VIBWR
        STA   FREQADJ+1
        STB   FREQADJ
VIBNOV
; --- pitch env -> pitch, only if PDEP>0 ---
        LDA   PDEP
        BEQ   VIBWRF
        LDA   OPLV,U
        LDB   PDEP
        MUL                     ; D = OPLV*PDEP ; A = magnitude (0-98)
        STA   PDTMP
        JSR   FSH6            ; S226R: FREQADJ>>6 shared. D = freq>>6
        LDA   PDTMP
        MUL                     ; D = magnitude * (freq>>6 low) = raw delta (~1.5x freq at max depth)
        STD   VIBDLT            ; save before LDA PDIR clobbers A
        LDA   PDIR
        BEQ   PDOWN             ; 0 = down
; up: freq + raw delta -> reaches beyond an octave up at max depth; dial depth (55) to taste
        LDA   FREQADJ+1
        LDB   FREQADJ
        ADDD  VIBDLT
        BRA   PDPUT
PDOWN
; down: freq - (raw>>1) -> halved so freq stays above zero; reaches ~an octave down
        LDD   VIBDLT
        LSRA
        RORB
        STD   VIBDLT
        LDA   FREQADJ+1
        LDB   FREQADJ
        SUBD  VIBDLT
PDPUT
        STA   FREQADJ+1
        STB   FREQADJ
VIBWRF
; sample-mode rate scaling: match note-on's freq>>3 when a sample is loaded, else the pitch-modulated
; sample plays ~8x too fast. Applied to the final (base + vibrato + pitch-env) word, so the modulation
; ratio is preserved and the base pitch stays correct.
        JSR   SCALEW            ; S234b: sample -> SMPSCALE, boot saw -> SAWK trim (see note-on)
VIBFWR
; S91: apply pitch bend here - the one point both playback modes pass through - as a proportional
; scaling of the final frequency word. Sample tune keeps its own 8-bit factor upstream (TRIMAP, in
; the sample branch only); bend gets its own finer path and works in both modes.
        TST   PBDEV
        BEQ   VIBFW1
        JSR   PBAPPLY
VIBFW1
        JSR   FWRPAIR           ; write FREQADJ to both oscillators of voice VIDX
; --- detune layer follows the sweep: rewrite the detune osc (16+V) from the modulated freq ---
        LDA   MIX
        BEQ   VIBDD             ; detune off -> nothing to follow
        LDX   #OBASEF
        LDB   VIDX
        ASLB                    ; voice*2
        ABX                     ; X -> OBASEF[voice] (hi at ,X / lo at 1,X)
        LDA   FREQADJ+1
        STA   ,X                ; OBASEF[voice] = modulated freq (hi)
        LDA   FREQADJ
        STA   1,X               ;                                 (lo)
        LDA   DAMT
        LDB   VIDX
        JSR   DTFREQCALC        ; recompute + write detune osc from the modulated base
VIBDD
        LDB   VIDX              ; restore voice index for caller
VIBEND
        RTS

; ===== FWRPAIR: write FREQADJ (lo at FREQADJ, hi at FREQADJ+1) to both oscillators =====
; of the swap pair for voice VIDX (osc 2V and 2V+1). EC00+osc=freq lo, EC20+osc=freq hi.
; Optimized: LEAX to the osc-2V base, then freq lo at ,X and hi at $20,X; +1 for partner.
; Clobbers A,B,X. Voice index must be in VIDX. Used by NOTEON and VIBR.
FWRPAIR
        LDB   VIDX
        ASLB                    ; B = 2V
        LDX   #$EC00
        LEAX  B,X               ; X = $EC00 + 2V (osc 2V freq-lo register)
        LDA   FREQADJ           ; freq lo
        STA   ,X                ; osc 2V freq lo  ($EC00+2V)
        STA   $01,X             ; osc 2V+1 freq lo ($EC01+2V)
        LDA   FREQADJ+1         ; freq hi
        STA   $20,X             ; osc 2V freq hi  ($EC20+2V)
        STA   $21,X             ; osc 2V+1 freq hi ($EC21+2V)
        RTS

; ===== DTSET: set up the detune oscillator (osc 16+V) for voice VIDX. =====
; If MIX=0, halt it (dry). Else compute a detuned copy of FREQADJ using FRACTAB[DAMT] (a curved
; +/-1 octave pitch-ratio map, sharp above DAMT 49, flat below), floored to at least +/-1 freq word
; so bass notes always move, and start it free-run on channel V.
; The detune osc's volume is tracked by AWWRITE; it halts with the voice in HALTOSC. Preserves A,B,X,U.
DTSET
        PSHS  A,B,X,U
; stash this note's base freq + seed the drift countdown, so DRIFTUPD can wander the detune later
        LDB   VIDX
        ASLB                    ; voice*2
        LDX   #OBASEF
        LEAX  B,X               ; X -> OBASEF[voice]
        LDA   FREQADJ+1
        LDB   FREQADJ           ; D = base freq (hi,lo)
        STD   ,X                ; OBASEF[voice] = base freq
        LDB   VIDX
        LDX   #DRIFTC
        LDA   #$20
        STA   B,X               ; DRIFTC[voice] = initial countdown
        LDA   MIX
        BEQ   DTHALT            ; mix 0 -> detune off, halt osc 16+V
; S212: the detune osc's size/res must match the PLAYBACK DOMAIN, not the boot default. With a
; sample it was still $38 from boot (resshift 2) while NOTEON feeds it the sample-domain word
; (resshift 9) -> address rate 128x too fast -> decimation hash + 24ms wrap clicks (the "metallic
; clicks"). Config per mode: no sample -> $38 (boot wave, unchanged). Looped sample -> $3F (32K,
; res 7 = resshift 9, the S68-proven free-run config; the full-buffer default loop matches the
; detune osc's 32K wrap exactly). One-shot sample -> detune stays HALTED: free-run never ends, so
; it would drone on after the primary halts at the sample end.
        LDA   SMPRDY
        BEQ   DTSYN             ; no sample -> boot-wave config
        LDA   LMODE
        BEQ   DTHALT            ; one-shot sample -> keep the detune layer dry
; S226: size the detune osc's table to the LOOP, not the buffer. The largest power-of-two
; table that FITS INSIDE the loop (vs the primary's smallest-that-CONTAINS): the detune osc
; is free-run, so it must wrap BEFORE the 8-zero loop-end sentinel - reading it would halt
; the layer dead on any short loop (previously it read the whole 32K and drifted instead).
; ENDPG 63 -> s=7 -> $3F, exactly the old full-buffer config. res=s keeps resshift 9 at
; every size; rate-1 words are already halved in DTFREQCALC, so all rates stay consistent.
        LDA   ENDPG
        INCA                    ; A = loop pages (1-64)
        CLRB
DTSZL   LSRA
        BEQ   DTSZE
        INCB
        BRA   DTSZL
DTSZE   INCB                    ; B = s = floor(log2(pages))+1 (1-7)
        LDA   #$09
        MUL                     ; D = 9*s; low byte = (s<<3)|s -> size s, res s, resshift 9
        LDA   SMPRES
        CMPA  #$08
        BNE   DTSZ9
        DECB                    ; S233b rate 4: res s-1 -> resshift 8 = the primary's domain
DTSZ9                           ; (s >= 1 -> res >= 0); the word needs no halving/doubling
        TFR   B,A               ; (DTCFG reloads B from VIDX, so B is free to clobber)
        BRA   DTCFG
DTSYN
        LDA   #$38              ; boot-wave domain: 32K table + res 0 -> resshift 2 (as at boot)
DTCFG
        LDB   VIDX
        ADDB  #$10              ; B = 16+V
        LDX   #$ECC0
        STA   B,X               ; size/res for the detune osc, per playback mode
; compute + write the detune osc freq via DTFREQCALC (DAMT only -> no drift applied at note-on)
        LDA   DAMT
        LDB   VIDX
        JSR   DTFREQCALC
        LDB   VIDX
        ADDB  #$10              ; B = 16+V (detune osc) for the control writes below
; control: phase-reset (halt+M0 -> accumulator reset) then free-run running, channel V
        LDA   VIDX
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = V<<4
        PSHS  A                 ; save channel<<4
        ORA   #$03              ; halt + M0 -> reset accumulator
        LDX   #$ECA0
        STA   B,X               ; $ECA0+osc: reset
        PULS  A                 ; A = V<<4 (free-run mode, running)
        STA   B,X               ; $ECA0+osc: run
        PULS  A,B,X,U,PC
DTHALT
        LDB   VIDX
        ADDB  #$10              ; osc 16+V
        LDA   VIDX
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = V<<4
        ORA   #$03              ; halt + M0
        LDX   #$ECA0
        STA   B,X               ; halt the detune osc
        LDX   #$EC40
        CLR   B,X               ; volume = 0
        PULS  A,B,X,U,PC

; FRACTAB: 21 entries indexed by DAMT (0-20, center 10 = unison). Each = |2^(cents/1200) - 1| in 0.8
; fixed (0-255), cents = (DAMT-10)*5, i.e. a linear +/-50 cents (+/-10 steps) chorus range. Sign
; (sharp/flat) is taken from DAMT vs 10 in DTSET; DAMT=10 -> frac 0 = unison.
FRACTAB
        FCB   7,7,6,5,4,4,3,2,1,1,0,1,1,2,3,4,4,5,6,7,8

; ===== RAND: 8-bit Galois LFSR pseudo-random generator. Returns next byte in A. RNGSTATE must be
; non-zero (seeded at boot). Preserves B, X, U. Shared by the LFO random waveform (and, later, detune
; drift). Period 255. =====
RAND
        LDA   RNGSTATE
        LSRA
        BCC   RNDNZ
        EORA  #$B8              ; maximal-length 8-bit tap
RNDNZ
        STA   RNGSTATE
        RTS

; ===== DTFREQCALC: write the detune oscillator's freq for a voice = OBASEF[voice] * ratio(effDAMT).
; Input: A = effective DAMT (0-20), B = voice index. Writes osc 16+V freq only (osc keeps running, so
; the pitch steps without a phase reset). Preserves A,B; clobbers X and the DT* scratch. =====
DTFREQCALC
        PSHS  A,B               ; [S]=effDAMT, [S+1]=voice
        LDX   #FRACTAB
        LDB   A,X               ; B = frac = FRACTAB[effDAMT]
        STB   DTMP
        LDB   1,S               ; voice
        ASLB                    ; voice*2
        LDX   #OBASEF
        LDD   B,X               ; D = base freq (hi,lo)
; S212: rate-1 samples ($0A = resshift 10 paged) play the detune osc at $3F (resshift 9), one
; domain to the left -> halve the base word here so every caller (note-on, sweep-follow, drift)
; stays consistent. Costs 1 LSB of detune precision at rate 1; the +/-1 floor still guarantees
; movement. Rates 2-3 ($09) and the boot wave pass through untouched.
        TST   SMPRDY
        BEQ   DFCNH             ; no sample -> no halving
        PSHS  A
        LDA   SMPRES
        CMPA  #$0A              ; rate 1?
        PULS  A                 ; (PULS of A alone leaves CC intact)
        BNE   DFCNH
        LSRA
        RORB                    ; halve: resshift-10 word -> resshift-9 domain
DFCNH
        STD   DTBASE
; delta = (base * frac) >> 8
        LDA   DTBASE+1          ; base lo
        LDB   DTMP
        MUL
        STA   DTMP2             ; (baseLo*frac)>>8
        LDA   DTBASE            ; base hi
        LDB   DTMP
        MUL
        ADDB  DTMP2
        ADCA  #$00              ; D = delta
        STD   DTDELTA
; unison / floor / sign (effDAMT vs 10)
        LDA   ,S
        CMPA  #10
        BEQ   DFCUNI
        LDD   DTDELTA
        BNE   DFCSGN
        LDD   #$0001            ; floor to +/-1 word
        STD   DTDELTA
DFCSGN
        LDA   ,S
        CMPA  #10
        BLO   DFCDN
        LDD   DTBASE
        ADDD  DTDELTA
        BCC   DFCPUT
        LDD   #$FFFF            ; clamp on overflow
        BRA   DFCPUT
DFCDN
        LDD   DTBASE
        SUBD  DTDELTA
        BCC   DFCPUT
        LDD   #$0001
        BRA   DFCPUT
DFCUNI
        LDD   DTBASE
DFCPUT
        STD   DTFREQ
        LDB   1,S               ; voice
        ADDB  #$10              ; osc 16+V
        LDX   #$EC00
        LDA   DTFREQ+1
        STA   B,X               ; freq lo
        LDX   #$EC20
        LDA   DTFREQ
        STA   B,X               ; freq hi
        PULS  A,B,PC

; ===== DRIFTUPD: per active voice (from TICKALL, B = voice index) slowly wander the detune amount by
; a bounded random offset. Off when DRAND=0 or MIX=0. Counts DRIFTC[voice] down; on 0 it picks a new
; random offset in [-DRAND,+DRAND], clamps DAMT+offset to 0..20, rewrites the detune osc freq, and
; reloads the (staggered) counter. Preserves B for the TICKALL loop; clobbers A,X. =====
DRIFTUPD
        TST   DRAND
        BEQ   DURET             ; drift off
        TST   MIX
        BEQ   DURET             ; detune off
        STB   DRVOICE
        LDX   #DRIFTC
        DEC   B,X               ; DRIFTC[voice]--
        BNE   DURET             ; not time yet
        JSR   RAND
        STA   DRTMP
; reload counter = (random & $7F) + $40 (slow per-voice-staggered drift, ~1.7-5 Hz)
        ANDA  #$7F
        ADDA  #$40
        LDB   DRVOICE
        LDX   #DRIFTC
        STA   B,X
; offset = (random * DRAND2)>>8 - DRAND ; effective = clamp(DAMT + offset, 0, 20)
        LDA   DRTMP
        LDB   DRAND2
        MUL                     ; A = random*(2*DRAND+1)>>8 = 0..2*DRAND
        SUBA  DRAND             ; -DRAND..+DRAND
        ADDA  DAMT
        BPL   DUC1
        CLRA                    ; clamp low to 0
DUC1
        CMPA  #20
        BLS   DUC2
        LDA   #20               ; clamp high to 20
DUC2
        LDB   DRVOICE
        JSR   DTFREQCALC        ; rewrite detune osc freq for this voice (S&H pitch step)
        LDB   DRVOICE           ; restore voice index for the TICKALL loop
DURET
        RTS

; ===== CA2ACK: VIA CA2 handshake pulse (our own copy of stock $8976) =====
; Drops our dependency on the stock-loaded routine so we can reclaim that sector.
; Masks interrupts, pulses CA2 low-then-high via the VIA PCR ($E20C). Touches only $E20C/CC.
CA2ACK
        PSHS  CC
        ORCC  #$50              ; mask IRQ+FIRQ
        LDA   $E20C             ; VIA peripheral control reg
        ANDA  #$FD
        STA   $E20C
        ORA   #$0E
        STA   $E20C             ; pulse CA2
        PULS  CC,PC             ; restore interrupts + return

; ASUSTGT: A = sustain target = (OAPK * ASUSV) >> 8. Preserves B (voice index).
ASUSTGT
        PSHS  B
        LDA   OAPK,U
        LDB   ASUSV
        MUL                     ; D = peak*sustain ; A = high byte = (>>8)
        PULS  B
        RTS

; FILTER env (peak = OFPK from velocity, sustain = OFPK*3/4, floor = FFLOOR)
FILTTICK
        LDA   OFST,U
        LBEQ  FEND
        CMPA  #$01
        BEQ   FATK1
        CMPA  #$02
        BEQ   FDEC1
        CMPA  #$03
        BEQ   FSUS1
        CMPA  #$04
        BEQ   FREL1
        RTS
FATK1
; 16-bit: {OFLV:OFLVL} += FATKV, saturate at {OFPK:00}
        PSHS  B
        LDD   OFLV,U
        ADDD  FATKV
        BCS   FATKSAT
        CMPA  OFPK,U
        BCC   FATKSAT
        STD   OFLV,U
        PULS  B
        RTS
FATKSAT
        LDA   OFPK,U
        STA   OFLV,U
        CLR   OFLVL,U
        LDA   #$02
        STA   OFST,U
        PULS  B
        RTS
FDEC1
; 16-bit: {OFLV:OFLVL} -= FDECV, floor at filter sustain target
        JSR   FSUSTGT           ; A = filter sustain target hi, B preserved
        PSHS  B
        PSHS  A
        LDD   OFLV,U
        SUBD  FDECV
        BCS   FDECHIT
        CMPA  ,S
        BLS   FDECHIT
        STD   OFLV,U
        PULS  A
        PULS  B
        RTS
FDECHIT
        PULS  A
        STA   OFLV,U
        CLR   OFLVL,U
        LDA   #$03
        STA   OFST,U
        PULS  B
        RTS
FSUS1
        JSR   FSUSTGT           ; A = filter sustain target hi, B preserved
        STA   OFLV,U
        CLR   OFLVL,U
        RTS
FREL1
; exponential filter release: step16 = ((OFLV-FFLOORV)_hi * RELK) + floor; taper to FFLOORV.
        PSHS  B
        LDA   OFLV,U
        SUBA  FFLOORV           ; A = amount above floor (hi)
        BLS   FRELHIT           ; at/below floor -> done
        LDB   FRELV+1           ; RELK
        MUL                     ; D = (above-floor) * RELK
        ADDD  #$0040            ; + floor step
        TFR   D,X
        LDD   OFLV,U
        PSHS  X
        SUBD  ,S++              ; D -= step16
        BCS   FRELHIT
        CMPA  FFLOORV
        BLS   FRELHIT
        STD   OFLV,U
        PULS  B
        RTS
FRELHIT
        LDA   FFLOORV
        STA   OFLV,U
        CLR   OFLVL,U
        CLR   OFST,U
        PULS  B
        RTS
FEND
        RTS

; FSUSTGT: A = filter sustain target = (OFPK * FSUSV) >> 8. Preserves B.
FSUSTGT
        PSHS  B
        LDA   OFPK,U
        LDB   FSUSV
        MUL
        PULS  B
        RTS



; ============================================================
; KBSERV: drain all pending keyboard bytes (non-blocking).
; Process each byte through the KBST state machine. Returns when
; no byte is pending (IFR bit2 clear). Call often to avoid drops.
; ============================================================
KBSERV
        LDA   $E20D
        BITA  #$04
        LBEQ KSRET             ; no byte pending -> return
        LDB   $E20A
        JSR   CA2ACK            ; ack (CA2 handshake, our copy)
        TSTB
        BPL   KSDATA            ; bit7 clear = data byte
; --- S89: sustain pedal. The R6500/11 reports the pedal as a bare status byte with NO data bytes:
;     $B8 = down, $B9 = up (decoded from the stock OS dispatcher at $89A1, which stores the state and
;     emits MIDI CC 127/0 the same way). Both have bit4 SET, so without this test the generic
;     on/off decode below would read them as NOTE-ON status and mis-arm the state machine. ---
        CMPB  #$B8
        BNE   KSPD1
        STB   SUSTAIN           ; nonzero = pedal down
        LDA   #$7F
        JSR   SUSCC             ; S90: transmit MIDI CC64 = 127, as the stock OS does
        BRA   KBSERV
KSPD1
        CMPB  #$B9
        BNE   KSSTAT
        CLR   SUSTAIN
        JSR   SUSREL            ; release everything that was being held
        CLRA
        JSR   SUSCC             ; S90: CC64 = 0
        BRA   KBSERV
KSSTAT
; status byte
        BITB  #$10
        BEQ   KSNOFF
        LDA   #$01              ; note-on status
        STA   KBST
        BRA   KBSERV            ; loop: drain next byte
KSNOFF
        LDA   #$03              ; note-off status
        STA   KBST
        BRA   KBSERV
KSDATA
        LDA   KBST
        BEQ   KBSERV            ; idle: ignore stray data, keep draining
        CMPA  #$01
        BEQ   KSONKEY
        CMPA  #$02
        BEQ   KSONVEL
        CMPA  #$03
        BEQ   KSOFFKEY
        CMPA  #$04
        BEQ   KSOFFVEL
        BRA   KBSERV
KSONKEY
        STB   KBKEY
        LDA   #$02
        STA   KBST
        BRA   KBSERV
KSONVEL
; S111: EXPAND the velocity range. The keyboard controller rarely reports below about 60 in normal
; playing - reaching lower means deliberately feathering the key - so the engine only ever saw the
; TOP HALF of its own dynamic range: amp peak 120-254 of 0-255, filter peak $9E-$BF of $80-$FF.
; Everything therefore sounded nearly as loud and nearly as bright however it was played.
; Mapping [VELFLR..127] onto [0..127] restores the full range to ordinary playing. Done here, once,
; before KBVEL is stored, so the amp peak, the filter peak AND the transmitted MIDI velocity all
; benefit and stay consistent with one another.
        SUBB  #VELFLR
        BCC   KSVEXP
        CLRB                    ; at or below the floor -> the softest the engine can do
KSVEXP
        LSLB                    ; x2: 67 counts of usable travel -> the full 0-127
        CMPB  #$80
        BCS   KSVST
        LDB   #$7F              ; clamp the top few counts
KSVST
        STB   KBVEL
        JSR   MONON
        CLR   KBST
        LBRA  KBSERV            ; S111: long branch - the expansion pushed this past BRA's reach
KSOFFKEY
        STB   KBKEY
        LDA   #$04
        STA   KBST
        LBRA  KBSERV
KSOFFVEL
        JSR   MONOFF
        CLR   KBST
        LBRA  KBSERV
KSRET
        RTS

; ============================================================
; SYNCP: copy PARMTAB values into the engine's live variables.
; PARMTAB entry = 4 bytes {specnum, value, min, max}.
; ============================================================
; SCALE99: A = param value 0-99 -> B = scaled to 0-253 (param*41/16). Trashes A,B.
; ===== SCALERES (S210): resonance scale - param 0-99 -> raw 0-177 (x115>>6) =====
; SCALE99's 0-253 put self-osc onset at param ~65 and the uncontrollable zone at ~80+. 99->177
; places onset at ~param 92-93: singing reachable only in the top few steps, chaos unreachable,
; and 40% finer resolution across the musical range (1.8 raw/step vs 2.56). Input A, result B.
SCALERES
        LDB   #115
        JSR   MSH6           ; S226R: MUL + >>6 shared. D = param * 115 (max 11385) ; D >>= 6 -> B = 0..177
        RTS

; ===== INFCALC (S211): input-filter cutoff DAC from param 3 =====
; DAC = SCALE99(param3) * FCEIL >> 8 - the same ceiling-following mapping the voice cutoff
; uses, so the whole 0-99 travel is distinct and 99 = the boot-calibrated brightest-safe.
; Replaces the hardcoded $C0 (which was ABOVE this unit's ceiling and sang, S120) and the
; meter's plain FCEIL. Preserves B; clobbers A and X (PFIND) - callers must have X free.
INFCALC
        PSHS  B
        LDA   #$03              ; param 3 = input filter frequency (wired at last - the
                                ; 'tune later via param 05' TODO, one renumbering later)
        JSR   PFIND
        JSR   SCALE99           ; B = 0..253
        LDA   FCEIL
        MUL                     ; D = scaled * ceiling
        STA   INFVAL            ; hi byte = 0..FCEIL
        PULS  B
        RTS

SCALE99
        LDB   #41
        MUL                     ; D = param*41
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D >>= 4 -> B = result low byte
        RTS

; PFIND: A = spec number to find. Scans PARMTAB. Returns value byte in A, X -> entry.
; Not found -> A=0 (safe default). Trashes B,X. Preserves U. Lets SYNCP be order-independent.
PFIND
        PSHS  A                 ; save target specnum
        LDX   #PARMTAB
        LDB   #NPARM2
PFLOOP
        LDA   ,X                ; entry's specnum
        CMPA  ,S
        BEQ   PFHIT
        LEAX  4,X
        DECB
        BNE   PFLOOP
        LEAS  1,S               ; not found
        CLRA
        RTS
PFHIT
        LEAS  1,S
        LDA   1,X               ; value byte
        RTS

SYNCP
        LDA   #SP_CUT           ; cutoff
        JSR   PFIND
        JSR   SCALE99           ; scale 0-99 -> 0-253
; S101: rescale that to the CALIBRATED CEILING instead of leaving FREF to clamp it. SCALE99 spans
; 0-253 but FREF never writes above FCEIL, so every parameter value above ceiling*16/41 produced an
; identical DAC value - a dead zone at the top of the control. Measured by Viz: the resonant peak
; stops moving around cutoff 45, which puts the effective ceiling near 109 and FCEIL near 140, so
; more than half the parameter range was doing nothing at all.
; DAC = SCALE99(param) * FCEIL / 256, using FCEIL directly as the multiplier: 253/256 is within half
; a percent of unity, so one 8x8 MUL and the high byte give param 99 -> the ceiling and param 50 ->
; half of it. The whole travel now maps to distinct, usable cutoffs, and it follows whatever FCAL
; measured on this particular unit rather than a fixed constant.
        LDA   FCEIL             ; all eight entries hold the same value (S86 collapses to the minimum)
        MUL                     ; D = SCALE99 result * ceiling
        TFR   A,B               ; keep the high byte = the rescaled cutoff
        STB   FCUTV
        STB   FFLOORV           ; env floor = base cutoff
; S112: reverse the sample buffer when the parameter changes. SYNCP only runs when a parameter has
; actually moved (S99), so this costs nothing while playing. RVLAST tracks the orientation the buffer
; is ACTUALLY in, so the two can never drift: after a load it is set from the restored parameter,
; because a slot saved while reversed contains reversed audio.
        LDA   #SP_REV
        JSR   PFIND
        CMPA  RVLAST
        BEQ   SYNCNRV
        STA   RVLAST
        TST   SMPRDY            ; no sample loaded -> nothing to reverse
        BEQ   SYNCNRV
        TST   ROTPG             ; S226: reverse operates on the LOGICAL buffer - unrotate
        BEQ   SYNCRV1           ; first; the loop section later in THIS sync pass re-rotates
        CLRA
        JSR   ROTAPPLY
SYNCRV1
        JSR   SMPREV
SYNCNRV
        LDA   #SP_RES           ; resonance
        JSR   PFIND
        JSR   SCALERES          ; S210: res-specific scale, 0-99 -> 0-RESMAX(177)
        STB   FRESV
        LDA   #SP_LFOR          ; LFO speed
        JSR   PFIND
        STA   LFORATE
; S230: build the phase increment for the selected RANGE (param 76 -> LFORTAB row):
;   LOW  (0): inc = 16p + 48   + (p*35>>6)*p  = 64 (the original minimum, EXACT) .. 1.10x
;             the original top - the old slowest quarter now spans params 1-40 (was 1-25)
;   HIGH (1): inc = 64p + 5632 + (p*46>>6)*p  = 0.90x .. 3.00x the original top
; Overlap 0.90x-1.10x per Viz. p=0 = off in both. Emulated across all 200 states.
        LDB   LFORATE
        BNE   LFRNZ
        CLRA                    ; rate 0 -> LFO off in either range (D = 0)
        BRA   LFRST
LFRNZ
        LDA   #SP_LFORNG
        JSR   PFIND             ; A = range 0/1 (absent -> 0 -> low; PFIND eats X)
        LDX   #LFORTAB
        TSTA
        BEQ   LFRLO
        LEAX  4,X               ; -> the HIGH row
LFRLO
        LDA   ,X                ; curve constant
        LDB   LFORATE
        JSR   MSH6              ; B = p*k>>6
        TFR   B,A
        LDB   LFORATE
        MUL                     ; D = curve term
        ADDD  2,X               ; + range base
        PSHS  A,B
        LDA   1,X               ; linear constant
        LDB   LFORATE
        MUL
        ADDD  ,S++
LFRST
        STD   LFOINC
        LDA   #SP_LFOD          ; LFO->filter depth
        JSR   PFIND
        STA   LFODEP
        LDA   #$06              ; spec 06 = sample tune (S54)
        JSR   PFIND
        ADDA  TRIMBAS           ; S96: k = value + this rate's base (50 -> in tune at every rate)
; (S89's note about bend riding on this 8-bit factor is obsolete - S91 gave bend its own
;  finer path in PBAPPLY; this line now sets the SAMPLE TUNE factor and nothing else.)
        STA   TRIMV             ; S91: sample tune only - bend no longer rides on this 8-bit factor
        LDA   #SP_LFOA          ; LFO->amp depth
        JSR   PFIND
        STA   LFOADEP
        LDA   #SP_LFOP          ; LFO->pitch depth
        JSR   PFIND
        STA   LFOPDEP
        LDA   #SP_LFOW          ; LFO waveform
        JSR   PFIND
        STA   LFOWAV
        LDA   #SP_LFOT          ; LFO trigger
        JSR   PFIND
        STA   LFOTRG
; amp envelope: attack/decay/release via 16-bit time->rate table; sustain via SCALE99
        LDA   #SP_AATK          ; amp attack
        JSR   PFIND
        JSR   RATE16            ; -> D = 16-bit rate
        STD   AATKV
        LDA   #SP_ADEC          ; amp decay
        JSR   PFIND
        JSR   RATE16
        STD   ADECV
        LDA   #SP_ASUS          ; amp sustain
        JSR   PFIND
        JSR   SCALE99
        STB   ASUSV
        LDA   #SP_AREL          ; amp release
        JSR   PFIND
        JSR   RELKCALC          ; -> B = release coefficient (graceful exp release)
        CLRA
        STD   ARELV             ; store as 16-bit (hi=0, lo=RELK)
; filter envelope: attack/decay/sustain/release/depth
        LDA   #SP_FATK          ; filter attack
        JSR   PFIND
        JSR   RATE16
        STD   FATKV
        LDA   #SP_FDEC          ; filter decay
        JSR   PFIND
        JSR   RATE16
        STD   FDECV
        LDA   #SP_FSUS          ; filter sustain
        JSR   PFIND
        JSR   SCALE99
        STB   FSUSV
        LDA   #SP_FREL          ; filter release
        JSR   PFIND
        JSR   RELKCALC          ; -> B = release coefficient
        CLRA
        STD   FRELV
        LDA   #SP_FDEP          ; filter env depth (0-98, 49=zero)
        JSR   PFIND
        STA   FDEPTH
; pitch envelope (51-56): attack/decay/release rates, sustain level, depth magnitude, direction
        LDA   #SP_PATK
        JSR   PFIND
        JSR   PRATE8
        STA   PATKR
        LDA   #SP_PDEC
        JSR   PFIND
        JSR   PRATE8
        STA   PDECR
        LDA   #SP_PSUS
        JSR   PFIND
        JSR   SCALE99
        STB   PSUSL
        LDA   #SP_PREL
        JSR   PFIND
        JSR   PRATE8
        STA   PRELR
        LDA   #SP_PDEP
        JSR   PFIND
        STA   PDEP
        LDA   #SP_PDIR
        JSR   PFIND
        STA   PDIR
        LDA   #SP_KTRK          ; keyboard tracking -> signed amount (param-49)
        JSR   PFIND
        SUBA  #49
        STA   KTRACK
        LDA   #SP_VFD           ; velocity -> filter depth
        JSR   PFIND
        STA   VFDEPTH
        LDA   #SP_VAMP          ; velocity -> amp depth
        JSR   PFIND
        STA   VAMPDEP
        LDA   #SP_VRES          ; S210: velocity -> resonance depth
        JSR   PFIND
        STA   VRDEP
        LDA   #SP_ERES          ; S210: filter env -> resonance depth (raw; 49 = zero)
        JSR   PFIND
        STA   ERDEP
        LDA   #SP_LFRS          ; S210: LFO -> resonance depth
        JSR   PFIND
        STA   LRDEP
; ---- tuning: TUNEOFS = (base note - 60) + (coarse - 24) signed semitone offset ----
        LDA   #SP_BASE          ; base note (0-99, default 60 = no transpose)
        JSR   PFIND
        SUBA  #60               ; signed offset from MIDI 60 (middle C)
        STA   TUNEOFS
        LDA   #SP_CRS           ; coarse tune (0-48, 24 = zero)
        JSR   PFIND
        SUBA  #24               ; signed -24..+24 semitones
        ADDA  TUNEOFS
        STA   TUNEOFS           ; combined signed semitone offset
        LDA   #SP_MWDMP         ; S155: mod wheel damping
        JSR   PFIND
        STA   MWDAMP
        LDA   #SP_MWEN          ; S155: mod wheel function
        JSR   PFIND
        STA   MWFUNC
        LDA   #SP_FINE          ; fine tune (0-98, 49 = zero)
        JSR   PFIND
        SUBA  #49               ; signed -49..+49 (sub-semitone)
        STA   TUNEFIN
        LDA   #SP_MIX           ; detune mix (0-99, 0 = dry)
        JSR   PFIND
        STA   MIX
        LDB   #166              ; dmix = MIX*166>>8  -> 0..64 (detune's share)
        MUL
        STA   MIXD              ; A = high byte = detune gain
        LDA   #128
        SUBA  MIXD
        STA   MIXP              ; primary gain = 128 - detune gain (constant-sum crossfade)
        LDA   #SP_DAMT          ; detune amount (0-98, 49=unison)
        JSR   PFIND
        STA   DAMT
        LDA   #SP_DRAND         ; detune random drift depth (0-4)
        JSR   PFIND
        STA   DRAND
        ASLA                    ; 2*DRAND
        INCA                    ; 2*DRAND+1 = span for the random offset
        STA   DRAND2

; ---- sample start / end + loop (playback trimming and looping) ----
; SAMPLE START: map param 09 (0-99) to a wtptr high byte (0..126, 256-byte units across the 32KB
; buffer). Note-on loads this into the oscillator wavetable pointer, so playback begins there.
        LDA   #SP_SSTART
        JSR   PFIND
        JSR   SCALE99           ; A(0-99) -> B(0-253)
        LSRB
        LSRB                    ; B >>= 2 -> 0..63 (512-byte PAGE index; 32K = 64 pages of 512B)
        CMPB  #62
        BLS   SSTOK
        LDB   #62               ; clamp: note-on pre-loads page SSTART+1, so keep SSTART+1 <= 63 (in-buffer)
SSTOK
        STB   SSTART
; LOOP MODE + LOOP START/END + SAMPLE END, all in 512-byte PAGE units for the pager (PGSERV). No $00
; marker is used in paged mode - PGSERV ends/loops via these page counters. Ranges are nested:
; SSTART <= LSTART <= LEND <= SEND. One-shot (LMODE=0) stops at SEND; forward loop (LMODE!=0) loops
; LSTART..LEND. (Reverse/ping-pong from the spec need backward paging - a later stage.)
        LDA   #SP_LMODE
        JSR   PFIND
        STA   LMODE             ; 0 = one-shot; nonzero = forward loop
; loop start (page units, clamped >= SSTART)
        LDA   #SP_LSTART
        JSR   PFIND
        JSR   SCALE99
        LSRB
        LSRB                    ; 0..63 page
        CMPB  SSTART
        BHS   LSCLOK
        LDB   SSTART            ; loop start can't be below sample start
LSCLOK
        STB   LSTART
; sample end (page units, clamped SSTART+1 .. 63)
        LDA   #SP_SEND
        JSR   PFIND
        JSR   SCALE99
        LSRB
        LSRB                    ; 0..63 page
        CMPB  SSTART
        BHI   SENDC1
        LDB   SSTART
        INCB                    ; sample end must be beyond sample start
SENDC1
        CMPB  #63
        BLS   SENDC2
        LDB   #63
SENDC2
        STB   SENDPG
        CMPB  LSTART            ; S234c: no cascade any more, so loop start may be stored above
        BHS   LSCAP             ; the sample end - cap it (effective = clamp(17, 15, 16))
        STB   LSTART
LSCAP
; loop end (page units, clamped LSTART .. SEND)
        LDA   #SP_LEND
        JSR   PFIND
        JSR   SCALE99
        LSRB
        LSRB                    ; 0..63 page  (B = loop-end page)
        CMPB  SENDPG
        BLS   LENDC1
        LDB   SENDPG            ; loop end <= sample end
LENDC1
        CMPB  LSTART
        BHS   LENDC2
        LDB   LSTART            ; loop end >= loop start
LENDC2
; effective end page = LEND if looping, else SEND
        TST   LMODE
        BEQ   ENDONE
        STB   ENDPG             ; loop: end page = loop end (B)
        LDA   SMPRDY
        LBEQ  SYNCPRT           ; no sample -> nothing in the buffer to scrub
; ---- S226: rotate the sample so the loop start sits at DOC offset 0 ----
; The free-run/swap-pair engine can only start a table at an aligned base (base 0), so an
; arbitrary loop START is implemented by physically rotating the 32K buffer left by LSTART
; pages (stock's param 66 precedent). Desired rotation = LSTART for exactly the notes the
; engine will take (loop on, no fine start, a resshift-9/10 rate); 0 for every pager case.
; ROTPG tracks the buffer's current rotation; data moves only when the target changes
; (~1s walk, audibly garbled while it runs - same class as SMPREV's toggle). After the
; rotate, the LIVE loop vars go physical: LSTART 0, ENDPG shifted; the params keep the
; logical values and this section recomputes the physical ones on every sync pass.
        LDA   LSTART            ; desired = loop start: every looped note is engine-played
                                ; now (S227: the SSTART and rate gates went with the pager)
        JSR   ROTSYNC           ; compare / defer / walk (S226c defer logic, shared with
                                ; the one-shot branch below)
        TST   ROTPG
        BEQ   ROTPHD            ; unrotated -> live vars are already physical
        LDA   ENDPG
        SUBA  ROTPG
        BCC   ROTF1             ; S226c: mid-defer, loop END can be edited below the OLD
        CLRA                    ; rotation -> clamp to 0 instead of wrapping (transient
ROTF1                           ; state; self-heals when the walk lands)
        STA   ENDPG             ; physical loop end page = logical - rotation
        CLR   LSTART            ; physical loop start = 0: the sized-table engine takes it
ROTPHD
        JSR   LPZSCRB           ; S222b: kill every $00 in the buffer (see the routine)
; S224: a looped note that will FREE-RUN needs an 8-zero sentinel AT THE LOOP END -
; that is what halts the oscillator so the restart service can send it back to the
; table start. A looped note that falls back to the PAGER must still have no marker
; anywhere (S150: a mid-buffer halt reads as a spurious swap and it plays on through).
; The conditions below mirror the routing in FREQWR exactly.
        LDA   ENDPG
        CMPA  #63
        BEQ   LPNOMK            ; FULL-buffer loop -> leave it on the hardware wrap that
                                ; 156/157 proved on hardware; the sentinel only buys
                                ; something when the loop ends short of the table.
        LBRA  ENDMK             ; S227: every other loop is engine-played -> sentinel at
                                ; the loop end (the pager's no-marker gates went with it)
LPNOMK
; S126: loop mode wants NO marker at all - the pager ends the note from ENDPG. Previously this
; branched past the marker machinery, which meant a marker left over from one-shot mode STAYED in
; the buffer and halted the oscillator wherever it happened to sit, pinning the sample length to
; whatever it was last set to. That is the "stuck on the first value" Viz found. Requesting position
; zero makes the removal path below restore the saved bytes and clear it.
        LDA   SMPRDY
        LBEQ  SYNCPRT           ; no sample -> leave the buffer alone
        CLRB                    ; desired marker position = none
        LBRA  SENDHAVE
ENDONE
        CLR   LPSCRB            ; S222b: looping off -> scrub again when it next comes on
        LDA   SENDPG
        STA   ENDPG             ; one-shot: end page = sample end
; S227: one-shot FINE SAMPLE START rides the same rotation: rotate the buffer so the
; sample start sits at offset 0; free-run then plays start -> sample-end marker (the
; wrapped-around pre-start material is never reached - the marker halts first, and it
; sits above the start because SENDPG > SSTART is clamped). SSTART stays LOGICAL
; everywhere; the marker translate below subtracts the rotation. Loop-off with no fine
; start rotates back to 0 exactly as before.
        LDA   SMPRDY
        LBEQ  SYNCPRT           ; no sample -> nothing to rotate or mark
        LDA   SSTART
        JSR   ROTSYNC           ; compare / defer / walk (shared with the loop branch)
; S150: the marker belongs ONLY to notes that will actually play in FREE-RUN. S125 placed it for
; EVERY one-shot, but the routing sends a non-zero SSTART (fine sample start) to the PAGER - and the
; pager uses oscillator halts as its page-swap signal. A marker sitting mid-buffer therefore causes a
; spurious halt that PGSERV reads as a swap, so it advances past the end and plays on through
; whatever follows: a loud buzz that lasts as long as the key is held. That is exactly what Viz found
; with sample start set and looping off.
; The rule is now symmetric with the loop case: pager -> NO marker, free-run -> marker.
ENDMK
; S125: FALL THROUGH to the marker placement instead of branching away. That LBRA dated from when
; every note went through the pager, where ENDPG alone ends the note and the comment's "unreachable
; in paged mode" was accurate. Since S68 one-shot notes at resshift-9 rates play FREE-RUN over the
; whole 32K buffer, and free-run has no end page - the only thing that stops it is a zero byte. With
; the marker never placed, sample end simply had no effect once looping was off, which is exactly
; what Viz found: start works either way, end works only while looping.
; The loop path above still branches away, so looping is untouched.
        LDA   SMPRDY
        LBEQ  SYNCPRT           ; no captured/loaded sample -> don't touch the buffer
; compute the marker position with the nested-range rule: the loop must sit INSIDE the sample range,
; so the effective loop end is clamped to the sample end (if you push loop end past sample end, it
; behaves as sample end). One-shot uses the sample end directly.
        LDA   #SP_SEND
        JSR   PFIND
        JSR   SCALE99           ; A(0-99) -> B(0-253)
        LSRB
        INCB                    ; B = sample-end position (0 excluded; 0 = "none")
        LDA   LMODE
        BEQ   SENDTR            ; one-shot -> marker at sample end - TRANSLATED like the loop
                                ; marker (S234c: this went straight to SENDHAVE, so with a fine
                                ; start the end marker sat 2*SSTART units too far into the
                                ; rotated buffer - one-shots ran far past param 16)
        PSHS  B                 ; [S] = sample-end position
        LDA   #SP_LEND
        JSR   PFIND
        JSR   SCALE99
        LSRB
        INCB                    ; B = loop-end position
        CMPB  ,S
        BLS   SENDLCLP          ; loop end <= sample end -> use loop end
        LDB   ,S                ; loop end past sample end -> clamp to sample end
SENDLCLP
        LEAS  1,S               ; drop the stashed sample-end position
; S226: physical marker position = logical - 2*ROTPG (position is 256B units, rotation
; 512B pages), SATURATING at 2. The raw loop-end param can resolve BELOW the loop start
; (the page clamps run on pages, not positions) - an unsaturated subtract underflows and
; SENDSET would write the 8 zeros at pos<<8 OUTSIDE DOC RAM, into the I/O/ROM space.
; Floor 2 = the end of physical page 0, matching the 1-page loop the page clamp produces.
; (Caught by whole-range emulation before the build - the exact S223 lesson.)
SENDTR
        SUBB  ROTPG
        BLS   SENDFLR           ; pos <= ROT -> degenerate edit -> pin
        SUBB  ROTPG
        BHI   SENDHAVE          ; still > 0 -> a real position
SENDFLR
        LDB   #$02
SENDHAVE
        CMPB  SENDPOS
        BEQ   SYNCPRT           ; unchanged -> nothing to do
        PSHS  U                 ; preserve U (used as the save-buffer pointer below)
        LDA   SENDPOS
        BEQ   SENDSET           ; none placed yet -> place directly (no restore, no hysteresis)
; S126: desired position ZERO means REMOVE the marker outright. There was no such path - a zero
; would have been treated as a position and written a marker at address $0000, on top of the sample.
        TSTB
        BNE   SENDNZ
        JSR   SRESTORE          ; put the sample's own 8 bytes back at SENDPOS
        CLR   SENDPOS           ; no marker in the buffer now
        PULS  U
        BRA   SYNCPRT
SENDNZ
; hysteresis: ignore single-unit moves. With mod-wheel editing enabled, ADC jitter of +/-1 on the
; currently-selected end param would otherwise flap the position between adjacent units - each flap
; restores and re-places the marker, repeatedly rewriting sample RAM and opening brief windows with no
; marker in memory, which is how the occasional note slipped past the end. A deliberate edit moves the
; position by several units and still applies; jitter never does.
        PSHS  B
        SUBB  SENDPOS           ; B = new - old (signed)
        BPL   SENDHYS
        NEGB                    ; |new - old|
SENDHYS
        CMPB  #$02
        PULS  B                 ; restore new position (PULS does not disturb the compare flags)
        BCC   SENDMOVE          ; moved by 2+ units -> a real edit, apply it (BCC = branch if B >= 2
                                ; unsigned after the CMPB; note the assembler has no BHS alias - a BHS
                                ; here previously assembled to NOTHING, silently, which made every
                                ; move fall through to the jitter-skip below: the marker never moved)
        PULS  U
        BRA   SYNCPRT           ; +/-1 unit = jitter -> leave the marker where it is
SENDMOVE
; marker moved: restore the 8 bytes we previously overwrote
        PSHS  B                 ; save new position
        JSR   SRESTORE          ; restore the 8 bytes under the OLD marker
        PULS  B                 ; B = new position
SENDSET
        STB   SENDPOS           ; remember new position
        TFR   B,A               ; new position -> high byte
        CLRB
        TFR   D,X               ; X = new marker address (new_pos << 8)
        LDU   #SENDSV8
        LDB   #$08
SSAVEL
        LDA   ,X
        STA   ,U+               ; save the sample byte we're about to overwrite
        CLR   ,X+               ; write one of the 8 marker zeros
        DECB
        BNE   SSAVEL
        PULS  U                 ; restore U
SYNCPRT
        RTS

; SRESTORE (S225 reclaim): put the 8 saved sample bytes back under the marker at
; SENDPOS. This sequence existed verbatim in two places - the remove path and the
; move path - so it is one routine now. Trashes A,B,X,U; both callers already have
; whatever they need on the stack.
SRESTORE
        LDA   SENDPOS           ; position is the HIGH byte of the buffer offset
        CLRB
        TFR   D,X
        LDU   #SENDSV8
        LDB   #$08
SRESTL
        LDA   ,U+
        STA   ,X+
        DECB
        BNE   SRESTL
        RTS

; RATE16: A = env time 0-99 -> D = 16-bit rate (RATE16TAB word lookup). Trashes A,B,X.
RATE16
        LDB   #2
        MUL                     ; D = A*2 (word index)
        LDX   #RATE16TAB
        LDD   D,X               ; load 16-bit rate word
        RTS

; PRATE8: A = param 0-99 -> A = 8-bit pitch-env rate = 100-param (higher param = slower stage)
PRATE8
        NEGA
        ADDA  #100
        RTS

; RELKCALC: A = release param 0-99 -> B = exponential release coefficient.
;   RELK = ((99-A)*52)>>6, clamped to >=2. Higher param = smaller RELK = slower release.
RELKCALC
        NEGA
        ADDA  #99               ; A = 99 - param
        LDB   #52
        JSR   MSH6           ; S226R: MUL + >>6 shared. D = (99-param)*52 ; D >>= 6 -> B = coefficient
        CMPB  #2
        BCC   RELKOK
        LDB   #2                ; floor at 2
RELKOK
        RTS


; ============================================================
; SEGREF: display-only refresh of ONE segment-column, then advance SEGCOL (0..7, wrap).
;   cols 0..6 = the seven segments (lit across both digits, active-low anodes: bit3=left/tens,
;   bit4=right/ones); col 7 = the mode decimal point (PARAM=left dot, VALUE=right dot).
;   Digit segment masks are reloaded from GETDISP each time SEGCOL wraps to 0, then walked with a
;   destructive LSR (one shift per column) exactly as PANEL did - so the mask always tracks SEGCOL
;   regardless of how many times per pass this is called.
;   Called once per FREF voice (8x/pass = one full refresh). PRESERVES A,B,X,U so FREF's voice index
;   (B) and voice pointer (U) survive the call.
; ============================================================
SEGREF
        PSHS  A,B,X,U
        LDA   SEGCOL
        BNE   SGLIT
; SEGCOL == 0: reload both digit segment masks
; S123: while ARMED, show the input level as BARS - the horizontal segments of both digits in
; tandem, as the stock OS does. Thresholds come from Viz's measurements on this instrument:
;     silence 2, quiet 30, normal 65, overdriven 99+
; so 16 / 48 / 84 sit between them, and the top bar lights at 84 - BEFORE clipping rather than at
; it, which is the whole point of a record meter.
        LDA   SMPSTAT
        CMPA  #$01
        BNE   SGNORM
        LDA   METPK
        LDB   #$03
        CMPA  #84
        BCC   SGMOK
        DECB
        CMPA  #48
        BCC   SGMOK
        DECB
        CMPA  #16
        BCC   SGMOK
        CLRB                    ; below 16 -> silence, no bars
SGMOK
        LDX   #METTAB
        LDA   B,X
        STA   PMSKH
        STA   PMSKL             ; both digits carry the same bars
        BRA   SGLIT
SGNORM
        JSR   GETDISP           ; A = tens digit, B = ones digit
        LDX   #SEGTAB
        PSHS  B                 ; save ones
        LDA   A,X               ; SEGTAB[tens]
        STA   PMSKH
        PULS  A                 ; A = ones
        LDA   A,X               ; SEGTAB[ones]  (X still = SEGTAB)
        STA   PMSKL
SGLIT
        LDA   SEGCOL
        CMPA  #7
        BEQ   SGDP
; segment column 0..6
        ORA   #$18              ; segment select + both anodes OFF (active-low)
        LSR   PMSKH
        BCC   SGNOH
        ANDA  #$F7              ; tens has this segment -> enable LEFT anode
SGNOH
        LSR   PMSKL
        BCC   SGNOL
        ANDA  #$EF              ; ones has this segment -> enable RIGHT anode
SGNOL
        STA   $E20F
        BRA   SGADV
SGDP
; column 7: mode decimal point
        LDA   #$07
        ORA   #$18
        TST   SLOTMODE
        BNE   SGDPBOTH          ; slot picker -> both dots
        TST   DMODE
        BNE   SGDPV
        ANDA  #$F7              ; PARAM mode -> left dot
        BRA   SGDPW
SGDPV
        ANDA  #$EF              ; VALUE mode -> right dot
        BRA   SGDPW
SGDPBOTH
        ANDA  #$E7              ; both dots (slot-pick indicator)
SGDPW
        STA   $E20F
SGADV
        INC   SEGCOL
        LDA   SEGCOL
        CMPA  #8
        BNE   SGDONE
        CLR   SEGCOL
SGDONE
        PULS  A,B,X,U
        RTS

; GETDISP: A=tens, B=ones for the current display (param number or value).
GETDISP
        LDA   SLOTMODE
        BEQ   GDNOSLOT
        LDA   SLOTNUM           ; slot picker active -> show the slot digit
        JMP   GDSPLIT
GDNOSLOT
        JSR   CURENT            ; X -> current PARMTAB entry
        TST   KPTMR             ; keypad entry running -> show the number being typed (either view)
        BEQ   GDNORM
        LDA   KPACC
        BRA   GDSPLIT
GDNORM
        TST   DMODE
        BNE   GDVAL
        LDA   ,X                ; PARAM: spec number
        BRA   GDSPLIT
GDVAL
; Show the EFFECTIVE value for the loop-range params (S234c: the same clamp the engine applies,
; via EFFLS/EFFLE). The stored value is untouched; pulling the sample range back open reveals it.
        LDA   ,X                ; spec number of the current param
        CMPA  #SP_LEND
        BEQ   GDLE
        CMPA  #SP_LSTART
        BNE   GDNLS
        JSR   EFFLS
        BRA   GDSPLIT
GDLE
        JSR   EFFLE
        BRA   GDSPLIT
GDNLS
        LDA   1,X               ; value
GDSPLIT
        CLRB
GDT     CMPA  #10
        BCS   GDDONE
        SUBA  #10
        INCB
        BRA   GDT
GDDONE
        EXG   A,B               ; A=tens, B=ones
        RTS

; EFFLS / EFFLE (S234c): effective loop start = clamp(p17, p15, p16); effective loop end =
; clamp(p18, effective loop start, p16). Param-value units (0-99). Clobber A,B,X.
EFFLS
        LDA   #SP_SSTART
        JSR   PFIND
        PSHS  A                 ; low bound = sample start
        LDA   #SP_SEND
        JSR   PFIND
        PSHS  A                 ; high bound = sample end
        LDA   #SP_LSTART
        JSR   PFIND
EFCLMP
        CMPA  ,S
        BLS   EFC1
        LDA   ,S                ; min(value, high)
EFC1
        CMPA  1,S
        BHS   EFC2
        LDA   1,S               ; max(., low)
EFC2
        LEAS  2,S
        RTS
EFFLE
        BSR   EFFLS
        PSHS  A                 ; low bound = effective loop start
        LDA   #SP_SEND
        JSR   PFIND
        PSHS  A                 ; high bound = sample end
        LDA   #SP_LEND
        JSR   PFIND
        BRA   EFCLMP

; CURENT: X -> PARMTAB + CURIDX*4
CURENT
        LDA   CURIDX
        LDB   #4
        MUL
        LDX   #PARMTAB
        LEAX  D,X
        RTS

; ============================================================
; PCLAMP: enforce the sample/loop range constraints on the STORED param values, so the display and
; every edit path (wheel + up/down buttons) reflect them. Rules:
;   - sample end  > sample start
;   - sample start <= loop start <= loop end <= sample end
; Edit-direction aware (the currently-selected param is the one being moved):
;   editing sample start/end -> that param pins at its bound, and the loop points CASCADE to follow.
;   editing loop  start/end  -> that param pins within [sample start .. sample end] and each other.
; Runs every main-loop pass but early-outs unless a range param is selected, so it is nearly free
; otherwise. Clamping the stored value is what makes the wheel "stop" at a bound: MWSERV re-baselines
; its pickup to the clamped value, so pushing further does nothing and pulling back moves it again.
; ============================================================
PCLAMP
        JSR   CURENT            ; X -> current PARMTAB entry
        LDA   ,X                ; current param spec number
        CMPA  #SP_SSTART
        BEQ   PCGO
        CMPA  #SP_SEND
        BEQ   PCGO
        CMPA  #SP_LSTART
        BEQ   PCGO
        CMPA  #SP_LEND
        LBNE  PCRET             ; not a range param -> nothing to do
PCGO
        STA   PCCUR             ; remember which param is being edited
; snapshot all four current values
        LDA   #SP_SSTART
        JSR   PFIND
        STA   PC_SS
        LDA   #SP_SEND
        JSR   PFIND
        STA   PC_SE
        LDA   #SP_LSTART
        JSR   PFIND
        STA   PC_LS
        LDA   #SP_LEND
        JSR   PFIND
        STA   PC_LE
; dispatch on edited param
; S234c: NO CASCADES. The old rules pushed the loop points along with every sample-start/end
; edit, and a pushed value never came back - one wheel overshoot ratcheted loop start/end to
; wherever the sweep had been (Viz: 15=36, 16=38 left 17 and 18 BOTH at 38). Now an edit
; changes only the edited param; the loop range is CLAMPED where it is used (SYNCP, display,
; EFFLS/EFFLE): effective loop start = clamp(17, 15, 16), effective loop end =
; clamp(18, effective loop start, 16). Defaults (17=0, 18=99) therefore loop the trimmed region.
        LDA   PCCUR
        CMPA  #SP_SSTART
        BEQ   PCESS
        CMPA  #SP_SEND
        BEQ   PCESE
        CMPA  #SP_LSTART
        BEQ   PCELS
; --- LOOP END edited: clamp into [effective loop start, sample end] ---
        JSR   EFFLS             ; A = effective loop start
        CMPA  PC_LE
        BHS   PCLE1             ; below it -> raise to it
        LDA   PC_LE
PCLE1
        CMPA  PC_SE
        BLS   PCWR
        LDA   PC_SE             ; above the sample end -> lower to it
        BRA   PCWR
; --- LOOP START edited: clamp into [sample start, sample end] ---
PCELS
        LDA   PC_LS
        CMPA  PC_SE
        BLS   PCLS1
        LDA   PC_SE
PCLS1
        CMPA  PC_SS
        BHS   PCWR
        LDA   PC_SS
        BRA   PCWR
; --- SAMPLE START edited: pin below sample end ---
PCESS
        LDA   PC_SS
        CMPA  PC_SE
        BLO   PCWR              ; start < end -> ok
        LDA   PC_SE
        BEQ   PCWR              ; end = 0 -> start = 0 (avoid underflow)
        DECA                    ; end - 1
        BRA   PCWR
; --- SAMPLE END edited: pin above sample start ---
PCESE
        LDA   PC_SE
        CMPA  PC_SS
        BHI   PCWR              ; end > start -> ok
        LDA   PC_SS
        INCA                    ; start + 1
; --- write back: ONLY the edited param can change now (S234c), A = its value ---
PCWR
        PSHS  A
        JSR   CURENT            ; X -> the edited entry (EFFLS clobbered X)
        PULS  A
        STA   1,X
PCRET
        RTS

; ============================================================
; MWSERV: mod wheel -> current param value, with pickup mode.
; Mod wheel is ADC channel 3, read at $ECE2 after setting VIA port B bits 2-3 = 11.
; Port B is also written by ROM interrupt handlers, so the read is done with interrupts
; masked (short critical section). Pickup: when the selected param changes, pickup re-arms;
; the value doesn't move until the wheel's mapped position crosses the current value.
; Crossing is detected by a sign change of (mappedWheel - currentValue).
; ============================================================
MWSERV
; ---- mod-wheel editing enable gate (param 71): if off, skip the wheel entirely. Lets the wheel be
;      disabled completely (e.g. to keep wheel jitter out of testing). ----
; S155: the wheel is always read. Parameter 71 now selects WHAT it does, not whether it runs:
;   0 = edit the selected parameter (the old behaviour, and the default)
;   1 = LFO speed   2 = LFO->pitch   3 = LFO->filter   4 = LFO->amp
; ---- read mod wheel (interrupt-safe critical section) ----
        PSHS  CC                ; save interrupt state
        ORCC  #$10              ; S231b: mask IRQ only (was #$50) - FIRQ (MIDI in) stays open;
                                ; MIDIRQ never touches port B or the ADC (see WHEELRD)
        LDA   $E200             ; current port B
        PSHS  A                 ; save it
        ORA   #$0C              ; mux bits 2-3 = 11 -> channel 3 (mod wheel)
        STA   $E200
        LDA   $ECE2             ; read ADC (mod wheel position 0..255)
        STA   MWVAL
; S155: DAMPING - an exponential average, sm += (raw - sm) >> k, with k from parameter 74. k = 0
; leaves the reading untouched. Each step of k halves the jitter excursion and roughly doubles the
; settling time, which is exactly the trade the player is choosing. Seeded from the first reading so
; the wheel cannot appear to sweep up from zero at power-on and edit something unbidden.
        LDA   MWSM
        BNE   MWSMOK
        LDA   MWVAL
        STA   MWSM              ; unseeded -> adopt the first reading
MWSMOK
        LDA   MWDAMP
        BEQ   MWSMDN
        LDB   MWVAL
        SUBB  MWSM              ; signed error
MWSMSH
        ASRB                    ; arithmetic shift keeps the sign
        DECA
        BNE   MWSMSH
        ADDB  MWSM
        STB   MWSM
        STB   MWVAL             ; everything downstream sees the smoothed position
MWSMDN
        PULS  A                 ; restore saved port B
        STA   $E200
        PULS  CC                ; restore interrupt state
; ---- S81: reject single-sample ADC outliers ----
; This read switches the mux to channel 3 and reads $ECE2 IMMEDIATELY. The DOC's ADC needs ~31us per
; conversion and a read taken mid-conversion returns a stale or partial value - which is exactly why
; WHEELRD (pitch) does flush/settle/discard/settle/read before trusting a sample. MWSERV never did,
; so it occasionally lands on a garbage reading. With a param selected the wheel EDITS THAT PARAM,
; so one bad sample steps the value: Viz sees random sudden cutoff steps while holding notes, with
; param 21 selected and the wheel untouched. (The same noise reaching the selection path is the
; likely cause of the "wheel jumps to another param" report.)
; Rather than add ~90us of masked settling delay to a routine that runs every pass, require two
; consecutive readings to agree: a lone spike is discarded, and since the history is updated either
; way the filter self-clears on the following pass. A real sweep moves ~1 count per pass, so a 24
; count window never impedes actual wheel movement.
; S109: the S94 median-of-3 was REMOVED. S95 recorded that it did not settle the jitter, and S100's
; adaptive deadband is what actually fixed it - so this was ~56 bytes of unproven filtering. If
; jitter ever returns at a specific spot on the track, it comes back; the reasoning is in S94.
; S93: HYSTERESIS. The outlier filter below only rejects jumps over 24 counts, so +/-1 count of ADC
; noise passes straight through - and wherever a wheel count straddles a parameter boundary that
; becomes a flicker between two values. Viz reports it worst about 3/4 of the way up the travel,
; which is $C0: the second-worst code boundary in a successive-approximation converter after
; mid-scale, where several bits flip at once. Requiring 3 counts of movement before accepting a
; reading kills the flicker and costs nothing, because the parameter has only 100 steps across 256
; wheel counts (2.56 counts per step) - 3 counts of deadband is about one step, and every value is
; still reachable.
        LDA   MWVAL
        SUBA  MWACC             ; movement since the last ACCEPTED reading
        BPL   MWHY1
        NEGA
MWHY1
; S100: ADAPTIVE deadband. A fixed 8-count window suppresses the jitter but is now the DOMINANT
; coarseness in the chain: 8 counts is 3.1 parameter steps, about 2.3 semitones of cutoff, against
; 0.75 for one parameter step and 0.42 for one DAC count. Jitter rejection and smooth sweeping were
; being traded against each other. They need not be: jitter happens when the wheel is STILL, so the
; window can be wide at rest and narrow while the wheel is genuinely moving.
;   no change at all      -> wind the tracking timer down
;   movement >= 8 counts  -> accept, and arm tracking
;   small move, tracking  -> accept, and re-arm (so a slow sweep stays fine-grained)
;   small move, at rest   -> reject; this is the jitter case
        TSTA
        BNE   MWMOVE
        TST   MWMOV
        BEQ   MWHOLD
        DEC   MWMOV             ; still -> let tracking expire
        BRA   MWHOLD
MWMOVE
        CMPA  #$08
        BCC   MWTAKE            ; deliberate move -> always accept
        TST   MWMOV
        BEQ   MWHOLD            ; small move with the wheel at rest -> jitter, reject
MWTAKE
        LDA   #$18              ; 24 passes (~0.2s at the current 9ms loop) of fine tracking
        STA   MWMOV
        LDA   MWVAL
        STA   MWACC
        BRA   MWHY3
MWHOLD
        LDA   MWACC
        STA   MWVAL
        BRA   MWHY3
MWHY3
        LDA   MWVAL
        SUBA  MWRAWL            ; delta from the previous raw reading
        BPL   MWABS1
        NEGA
MWABS1
        PSHS  A                 ; |delta|
        LDA   MWVAL
        STA   MWRAWL            ; history updated unconditionally, so a spike self-clears
        PULS  A
        CMPA  #$18              ; 24 counts
        BHI   MWDONE            ; outlier -> ignore this reading entirely
; ---- get current param entry ----
; S155: choose WHAT the wheel writes. Function 0 (default) targets the selected parameter, exactly
; as before. Values 1-4 point it at an LFO destination instead - and because the write lands in that
; PARAMETER's entry, the value persists, displays, saves and is picked up by SYNCP as though it had
; been dialled in by hand. The existing re-baseline logic below then applies to the target too.
; S208 belt-and-suspenders for the bend/edit crosstalk: while a REAL pitch-bend deflection is in
; flight, the param EDITOR stands down - you are performing, not editing, and any residual analog
; bleed can no longer walk a value. The LFO functions (71 = 1-4) stay live.
; S209: the gate now keys on |PBDEV| >= 16, NOT on PBACT. PBACT is the frequency-writer keep-alive
; and PBCALC re-arms it whenever PBDEV != 0 - which is PERSISTENT if the wheel's rest position
; settles a few counts outside the boot-calibrated dead band (the S173 drift, documented on this
; unit) or if the last MIDI bend didn't land exactly on centre (MBACT is never cleared). On such a
; unit PBACT never reaches zero and the S208 gate killed param editing OUTRIGHT (Viz, checklist_2
; follow-up). A real bend deflects ~100 counts; rest drift stays under ~10; 16 separates them.
        LDA   PBDEV
        BPL   MWPBP
        NEGA                    ; |PBDEV| (NEGA($80)=$80 still gates: -128 IS a full deflection)
MWPBP
        CMPA  #$10
        BCS   MWNOBND           ; < 16 counts: rest drift/jitter -> editor stays live
        TST   MWFUNC
        LBEQ  MWDONE            ; function 0 (edit selected param) + real bend -> stand down
MWNOBND
        JSR   MWTGT             ; S227b: shared with MIDI CC1 receive -> X = target entry
; ---- re-baseline (and don't act) if: param changed, OR value changed externally (buttons). ----
; In either case the wheel must move past the threshold from the new baseline to take over.
; MWPIDX is initialised to $FF at boot, so the first pass re-baselines (handles power-on).
        LDA   CURIDX
        CMPA  MWPIDX
        BNE   MWREBASE          ; selected param changed
        LDA   1,X               ; current value
        CMPA  MWLASTV
        BNE   MWREBASE          ; value changed by buttons (or other) since we last set it
; ---- same param, value unchanged: has the wheel moved past threshold from baseline? ----
        LDA   MWVAL
        SUBA  MWBASE            ; signed displacement from baseline
        BPL   MWDPOS
        NEGA
MWDPOS
        CMPA  #$08              ; threshold to take over (raised 4->8, less twitchy)
        BLS   MWDONE            ; within deadband -> leave value (buttons/switch safe)
        JSR   MWMAP             ; wheel takes over: map and write
        CMPA  MWLASTV           ; did the wheel actually change the value?
        BEQ   MWWSK             ; no change (wheel held steady) -> let the display settle back
        LDB   #VTMOUT           ; value changed -> show it and (re)arm the revert timer
        STB   VTMR
        LDB   #$01
        STB   DMODE
MWWSK
        STA   1,X
        STA   MWLASTV           ; keep our value-record in sync
        LDB   MWVAL             ; re-baseline pickup to the wheel's current position: once the wheel
        STB   MWBASE            ; stops moving, ADC jitter within the deadband stops re-writing (the
                                ; value freezes and the temp value-display can settle back to PARAM)
        BRA   MWDONE
MWREBASE
        LDA   CURIDX
        STA   MWPIDX            ; remember current param
        LDA   1,X
        STA   MWLASTV           ; remember current value
        LDA   MWVAL
        STA   MWBASE            ; baseline = current wheel; no jump until it moves past threshold
MWDONE
        RTS

; MWTGT (S227b): X -> the wheel's target param entry - the selected param (function 0)
; or the param-71 LFO destination (functions 1-4). Shared by the local wheel handler and
; the MIDI CC1 receive path, so both edit exactly the same thing.
MWTGT
        LDA   MWFUNC
        BEQ   MWTGT1
        DECA
        LDX   #MWTGTAB
        LDA   A,X               ; target spec number
        JMP   PFIND             ; tail call; PFIND leaves X at the entry it found
MWTGT1
        JMP   CURENT            ; tail call; X -> {spec,val,min,max}

; ===== CC1SRV (S228b): apply the latest received CC1, once per main-loop pass =====
; See MIDCC1 for why this is coalesced. External-edit semantics as before: MWLASTV is
; deliberately not updated, so the local wheel re-baselines rather than fighting.
CC1SRV
        TST   CC1PEND
        BEQ   CC1RTS
        CLR   CC1PEND           ; (a value received while 77 = off is DISCARDED, not deferred)
        LDA   #77               ; S232: param 77 = MIDI mod wheel receive (0 on, 1 off). PFIND
        JSR   PFIND             ; runs at most once per pass and only when a CC1 arrived - the
        TSTA                    ; S228b flood rule holds (never per message).
        BNE   CC1RTS            ; off -> the Mirage's own wheel is the only editor
        LDA   CC1VAL
        STA   MWVAL             ; parameter hand-off to MWMAP (ADC refill overwrites later)
        JSR   MWTGT             ; X -> target entry (selected param / param-71 destination)
        JSR   MWMAP             ; A = min + (value*span)>>8, clamped
        CMPA  1,X
        BEQ   CC1RTS            ; no change -> don't re-arm the display
        STA   1,X               ; the external edit (SYNCP's checksum picks it up)
        LDB   #VTMOUT
        STB   VTMR              ; flash the new value, as the wheel does - on a rackmount
        LDB   #$01              ; this is the only feedback there is
        STB   DMODE
CC1RTS
        RTS

; MWMAP: map MWVAL (raw wheel 0..255) to current param range -> A. X -> param entry.
;   val = min + (wheel * (max-min+1)) >> 8, clamped to max.
MWMAP
        LDB   3,X               ; max
        SUBB  2,X               ; B = max - min
        INCB                    ; span = max-min+1
        LDA   MWVAL             ; wheel 0..255
        MUL                     ; D = wheel * span ; A = >>8 offset
        ADDA  2,X               ; + min
        CMPA  3,X
        BLS   MWMP1
        LDA   3,X               ; clamp to max
MWMP1
        RTS

; ============================================================
; SAMPLING ENGINE
; Audio comes in on the ES5503 ADC at $ECE2 (same register as the mod wheel, different mux).
; Input source param 04: 0=mic (mux ch0), 1=line (mux ch1). Mux = VIA port B bits 2-3.
; Sample RAM = 128KB seen through a 32KB window at $0000-$7FFF, banked by port B bits 0-1.
; Capture fills all 4 banks (128KB). $00 bytes are forced to $01 (oscillator halts on $00).
; SMPSERV runs each main loop: handles REC button (arm / manual-start / auto-trigger).
; ============================================================

; SMPSERV: poll the REC button and drive the sampling state machine.
SMPSERV
        LDA   #$06              ; REC SEQ button = column 6
        JSR   SCANC
        ANDA  #$20              ; row 0 sense = bit 5 ($20); 0 = pressed (active low)
        BNE   SMPNOPR           ; not pressed
; --- REC pressed ---
        LDA   SMPREC
        LBNE SMPSRET           ; still held from before -> ignore (debounce)
        LDA   #$01
        STA   SMPREC            ; latch press
; dispatch on current state
        LDA   SMPSTAT
        BEQ   SMPARM            ; idle -> arm
        CMPA  #$01
        BEQ   SMPMAN            ; armed -> (manual) start, or ignore in auto
        LBRA SMPSRET           ; already recording -> ignore
SMPARM
        LDA   #$01
        STA   SMPSTAT           ; -> armed
        CLR   METPK             ; S114: start the level meter from silence
        LDA   #$01
        STA   METDEC            ; S117: prime the decay divider
        LDA   #$01
        STA   METFRF            ; S120: open the input filter on the first armed pass
        LDA   $E200
        STA   METPB             ; S122: remember port B so disarming can restore it
        JSR   SMPSRC            ; set the source mux ONCE and LEAVE it - see below
        BRA   SMPSRET
SMPMAN
; armed: in manual mode (param 02 = 0) a second press starts recording now.
; S151: the second press starts capture in BOTH modes. In auto mode it means "begin listening":
; SMPCAP runs its setup and pre-roll, then waits inside the capture loop for the threshold.
        JSR   SMPCAP            ; manual: record now. auto: pre-roll, then wait for the threshold
        BRA   SMPSRET
SMPNOPR
        CLR   SMPREC            ; button released -> clear latch
; if armed in AUTO mode, check input level against threshold to auto-start
        LDA   SMPSTAT
        CMPA  #$01
        BNE   SMPSRET           ; not armed -> nothing to do
; S118: the S117 main-loop volume clearing is removed - it fought the tick handler instead of
; stopping it. The gate now lives in AWRV, where the level is computed.
; S119: OPEN THE INPUT FILTER before reading. This is why the meter saw nothing while sampling
; worked: the input path runs through filter channel 7, and SMPCAP opens it as part of its setup
; (resonance $18, cutoff $C0) while at boot it is closed - PRELINIT zeroes the DACs and FCAL closes
; every channel. So while armed the input simply never reached the converter, and the only thing the
; meter could see was the 5503's own output leaking through the mixed tap.
; The SAME values the capture uses are written here, so the meter measures what the capture will
; actually record. Written every pass, because the CV is a drooping sample-and-hold; the write lands
; well before the 54us ADC settle in SMPRD1.
; S120: use the CALIBRATED ceiling, not SMPCAP's hardcoded $C0. $C0 is ABOVE the self-oscillation
; threshold this unit measured at boot, so it drove the input filter into singing - discrete tones at
; 3900 and 4352 Hz in Viz's recording, which is the same 4kHz region S84 measured when voice channels
; tipped over. That is BOTH symptoms in one: the noise while monitoring, and the meter not responding,
; because the converter was reading the filter's own oscillation instead of the input.
; Refreshed every 16 passes rather than every pass. Each DAC write is a fixed-size glitch (S80), so
; three writes at 111Hz was itself injecting noise into the very signal being metered; the CV is a
; slow-drooping sample-and-hold, so a refresh every ~150ms is ample.
        DEC   METFRF
        BNE   SMPNOFL
        LDA   #$10
        STA   METFRF
        LDA   #$18
        STA   $E40F             ; input filter resonance, channel 7
        JSR   INFCALC           ; S211: param 3, recomputed each refresh (~150ms) so the input
                                ; filter is LIVE-TUNABLE while armed - select param 3 and hear
                                ; the monitored input change. X is free here (reloaded below).
        LDA   INFVAL
        STA   $E41F             ; preload DAC channel 7
        STA   $E417             ; VF cutoff channel 7 - written LAST, the mux parks here
SMPNOFL
; S114: armed, so read the input level for the LEVEL METER. This now happens in BOTH trigger modes;
; auto mode reuses this same reading for its threshold test instead of taking a second one.
; S122: read the converter DIRECTLY - do NOT call SMPRD1. SMPRD1 selects the source mux and then
; RESTORES port B on every call, and port B bits 2-3 are the audio mux itself. Doing that once per
; main-loop pass switched the audio path back and forth ~111 times a second: each switch is a click,
; a train of them is a grind, and because the loop slows as voices are added the grind slowed with
; keys held - exactly what Viz heard. SMPCAP does not do this; it sets the source once and then reads
; $ECE2 continuously, which is the pattern copied here. The mux was set on arming and nothing else
; touches port B while armed, so a plain read is correct.
        LDA   $ECE2             ; discard - starts a fresh conversion
        LDX   #$0014
SMPMW
        LEAX  -1,X
        BNE   SMPMW             ; ~54us, past the converter's 31us
        LDA   $ECE2             ; settled sample
        SUBA  #$80              ; centre -> magnitude
        BPL   SMPMAGOK
        NEGA
SMPMAGOK
        STA   GEN0              ; |level| 0..127-ish
; Peak hold: rise instantly, fall one count per pass (~1.1s from full at the 9ms loop). One reading
; per pass catches almost nothing of a transient source - the peak is what makes the meter readable.
        CMPA  METPK
        BLS   SMPMDEC
        STA   METPK
        BRA   SMPMDON
SMPMDEC
; S117: decay one count per EIGHT passes rather than every pass. At the 9ms loop the old rate fell
; from full in about half a second, so the number flickered too fast to read; this gives roughly
; four seconds, which is steady enough to note a value and still tracks a falling source.
        TST   METPK
        BEQ   SMPMDON
        DEC   METDEC
        BNE   SMPMDON
        LDA   #$01              ; S124: one count per PASS. With four bar states rather than a
        STA   METDEC            ; two-digit number, the twitchiness that made 1-per-pass unreadable
        DEC   METPK             ; as digits does not apply - bars only change at three thresholds.
                                ; 1.1s from full; the top bar drops in about 0.4s, which is what
                                ; setting a level actually needs.
SMPMDON
        LDA   #$04              ; S210: trigger mode is now spec 4 (was 2)
        JSR   PFIND             ; trigger mode
        BEQ   SMPSRET           ; manual mode -> the meter is enough; wait for the second press
; S151: the main-loop threshold test is REMOVED - detecting here and only then entering SMPCAP put
; the entire pre-roll between the trigger and the first stored byte. The test now lives inside the
; capture loop, after the pre-roll.
SMPSRET
        RTS

; SMPSRC: set VIA port B mux to the selected input source (param 04), interrupts already masked.
; mic (0) -> mux ch0 (bits 2-3 = 00); line (1) -> mux ch1 (bits 2-3 = 01).
; Returns with port B set; caller restores. Leaves A = saved original port B.
SMPSRC
        LDA   $E200
        STA   GEN1              ; save original port B
        ANDA  #$F3              ; clear mux bits 2-3
        PSHS  A
        LDA   #$02              ; S210: input source is now spec 2 (was 4)
        JSR   PFIND             ; A = source (0=mic,1=line)
        TFR   A,B
        PULS  A
        TSTB
        BEQ   SMPSRC1           ; mic -> mux 0 (bits clear)
        ORA   #$04              ; line -> mux ch1 (bit 2 set)
SMPSRC1
        STA   $E200
        LDA   GEN1              ; return original in A
        RTS

; SMPRD1: read ONE input sample (interrupt-safe). A = byte. Used for auto-trigger level check.
; S161: SMPRD1 removed - dead since S122, when the level meter stopped calling it and began
;       reading the converter directly with the mux set once at arming. Reclaimed to fund
;       the header-read retry below.

; ============================================================
; SMPCAP: capture 128KB from input into sample RAM, paced by VIA Timer 1 (the stock-OS method).
; Timer 1 free-runs at the sample rate; SYNC halts the CPU until each timer tick, so we read
; exactly one ADC sample per tick -> precise 10-32kHz rates independent of code speed.
; Reverse-engineered from the stock OS capture loop at $9819. $00->$01. Fills 4 banks (128KB).
; ============================================================
SMPCAP
        LDA   #$02
        STA   SMPSTAT           ; -> recording
; --- look up the Timer 1 latch value for the chosen rate (16-bit, lo/hi) ---
        LDA   #$01              ; spec 01 = sample rate
        JSR   PFIND             ; A = rate 1..5
        DECA
        PSHS  A                 ; save rate index
        LDX   #SMPSHTAB         ; playback frequency shift for this rate (always 3; see tables)
        LDB   A,X
        STB   SMPSHFT
        LDX   #SMPRESTB         ; paged-playback size/res for this rate (the actual rate scaler)
        LDB   A,X
        STB   SMPRES
        LDX   #TRIMBTB          ; S96: and this rate's sample-tune base
        LDB   A,X
        STB   TRIMBAS
        LDX   #SMPLTAB          ; calibrated T1 latch for this rate (bus-stall compensated)
        LDB   A,X
        STB   SMPLATCH
        PULS  A                 ; rate index
        LDX   #SMPPRTAB         ; software prescaler: store every Nth timer tick
        LDA   A,X
        STA   SMPPRE            ; N for this rate (effective rate = 29.5kHz / N)
        PSHS  CC
        ORCC  #$50              ; mask CPU IRQ (SYNC still wakes on the IRQ line)
        LDA   $E200
        STA   SMPPBSV           ; save port B to restore at end
        JSR   SMPQSC            ; S56: quiesce oscillators (stock-informed; see routine)
; --- Capture setup matched to the working build (which recorded real speech). Earlier "silencing"
;     additions - halting all 32 oscillators, zeroing the input-filter resonance, and closing the
;     voice filters - turned out to make the capture record a pure sine artifact instead of the
;     input. The working build did none of that: it simply opened the input filter (with a little
;     resonance) and recorded. Restoring that exact setup. ---
; --- set up the analog INPUT FILTER (channel 7) exactly as the stock OS does during capture ---
; The MAME filter map (coefficients_w) is authoritative: for channel 7, $E417 = VF (cutoff),
; $E40F = VQ (resonance), and $E41F = the filter DAC PRELOAD. The stock capture writes ALL THREE -
; crucially the PRELOAD DAC ($E41F), which sets the input filter DAC's operating point. We had never
; written it (it was avoided after an early boot hang), and without it the input filter never biases
; correctly, so the ADC sees a slow/near-frozen signal = the ~150Hz muffle. Writing it here, once,
; for channel 7 only (as stock does), should let the full input bandwidth through.
; Write ORDER matters (working model, S45): the CV hardware appears to be one shared DAC + mux that
; PARKS on the last-written channel, driving it continuously; un-parked channels' S&H caps droop.
; Evidence: measured capture-long cutoff droop when resonance was written last (unified3 ramp), and
; droop proceeding despite 35ms cutoff+preload strobes that ended parked on the preload (unified4).
; So: resonance and preload (one-time operating-point preset) first, CUTOFF LAST - the mux then sits
; on the input cutoff for the entire capture, holding it at full value with zero droop.
        LDB   #$18              ; resonance = $18 (24), matching the stock capture value
        STB   $E40F             ; VQ (resonance) channel 7
        LDA   INFVAL            ; S211: input filter cutoff/preload from param 3 (0..FCEIL,
                                ; ceiling-clamped by construction - the old hardcoded $C0 sat
                                ; ABOVE the ceiling and sang). Computed by INFCALC at capture
                                ; start, X-safely, before the DOC pointer was established.
        STA   $E41F             ; PRELOAD DAC channel 7 (one-time preset - never re-strobed mid-capture)
        STA   $E417             ; VF (cutoff) channel 7 - LAST: mux parks here, driving the CV
; --- let the analog filter settle before recording, so any opening transient (a brief ring as the
;     cutoff voltage slews) dies out before the capture loop starts, rather than being recorded. ---
        LDX   #$4000            ; countdown; ~5 cycles/iter @2MHz ~= 40ms settle
SMPFSET LEAX  -1,X
        BNE   SMPFSET
; --- VIA port A = $06, exactly as the stock OS sets it right before its capture loop. Port A bits
;     0-2 drive a 74LS145 decoder (column select); the stock capture holds column 6 here. We were
;     clearing it to $00 (column 0), which may leave the analog input path / ADC mux in the wrong
;     state so the audio never reaches the converter. Matching the stock OS's proven capture setup. ---
        LDA   #$06
        STA   $E20F
; --- program VIA Timer 1 at a fixed, PROVEN one-byte rate (29.5kHz, latch $42 from the working
;     build). The lower effective sample rates come from a SOFTWARE PRESCALER (store every Nth
;     tick), NOT a slower timer - because 16-bit timer latches (needed for sub-7.8kHz) don't take
;     effect reliably on this hardware (the high byte was ignored -> capture ran at full speed).
;     A one-byte latch always works. ---
        LDA   #$42              ; T1 latch low = 66 -> ~29.5kHz (matches the stock OS capture rate)
        STA   $E206
        CLRA
        STA   $E207             ; latch high = 0 (one-byte rate - always reliable)
        LDA   $E20B
        STA   SMPACRS           ; save ACR
        ORA   #$40              ; T1 continuous (free-run) mode
        ANDA  #$7F              ; PB7 not driven by timer
        STA   $E20B
        LDA   SMPLATCH          ; S53: calibrated per-rate latch (was fixed #$42)
        STA   $E204             ; counter low
        CLRA
        STA   $E205             ; counter high = 0 (loads counter + starts timer)
        LDA   #$C0
        STA   $E20E             ; IER: enable Timer 1 interrupt
; --- compute mux/source bits once into GEN2 (port B with bank+mux cleared) ---
        LDA   SMPPBSV
        ANDA  #$F3              ; clear mux bits 2-3 (leave bank/other bits). Mux = port B bits 2-3
                                ; (MAME: m_mux_value=(portB>>2)&3): 00=mic, 01=line, 10=pitch, 11=mod.
        STA   GEN2
        LDA   #$02              ; input source (S210: spec 2, was 4)
        JSR   PFIND
        TSTA
        BEQ   SMPC_MIC
        LDA   GEN2
        ORA   #$04              ; line -> mux 1 (port B bit 2 set). mic -> mux 0 (bits clear).
        STA   GEN2
SMPC_MIC
; S152: read the trigger mode and threshold HERE, while X is still free. PFIND does LDX #PARMTAB -
; it DESTROYS X - and in unified112 I called it after LDX #$0000 had set the DOC RAM write pointer.
; The capture then wrote 32KB of ADC samples starting inside PARMTAB instead of into DOC RAM, which
; is why nothing was recorded AND why parameter 2 displayed garbage: its value had been overwritten
; with audio. Reading the parameters before the pointers are established removes the hazard entirely
; rather than papering over it with a save/restore.
        LDA   #$04              ; S210: trigger mode spec 4 (was 2)
        JSR   PFIND
        STA   SMPAUT            ; 0 = manual, non-zero = auto
        LDA   #$05              ; S210: threshold spec 5 (was 3)
        JSR   PFIND
        STA   SMPTHR
        JSR   INFCALC           ; S211: input-filter cutoff from param 3 - computed HERE, while
                                ; X is still free (PFIND destroys X; the S152 lesson). The
                                ; filter-setup block below and both keep-alives use INFVAL.            ; threshold, same 0-127 magnitude scale as the level meter
        LDU   #$ECE2            ; U -> ADC register (fast pointer read)
        LDA   GEN2              ; port B with bank 0 + source mux
        STA   $E200
        LDX   #$0000            ; write into DOC $0000 (the 32768-sample buffer the oscillators read)
        LDA   $E204             ; clear any pending timer IRQ
; --- capture loop with an 8x SOFTWARE PRESCALER. The first-gen Mirage's external ADC (AD7574) needs
;     real conversion time; at the full ~29.5kHz tick rate, ~8 consecutive reads return the SAME
;     (still-converting) value, so the input was being oversampled ~8x = heavily low-passed to a
;     muffled ~200Hz tone (the higher a note is played, the more this pitches back up toward speech -
;     the tell that the content is there but 8x too slow). Here we SYNC through 8 timer ticks between
;     stores (~270us), giving each conversion time to finish, so every stored byte is a fresh sample.
;     Effective capture rate ~3.7kHz (~1.8kHz bandwidth - plenty for speech), ~8.9s into the buffer. ---
; --- PRE-ROLL: run the capture cadence WITHOUT storing for a stretch first, to swallow the input-
;     path startup transient. When capture begins we've just switched the input source (port B mux)
;     and written the input-filter cutoff/resonance/preload DACs; those DACs slew to their operating
;     point over tens of ms, producing a brief high-pitched "squawk". Reading (but not storing) ~2000
;     prescaled samples (~0.5s) lets that transient die before recording, so it never lands at the
;     head of the sample. ---
; S70: the pre-roll must be a fixed WALL TIME, not a fixed sample count. At 2000 samples it is
; 0.64s at rate 1 but only 0.34s at rate 2 and 0.24s at rate 3, so the squawk described above -
; Viz hears it as a chirp whenever Rec starts - outlives the pre-roll at the faster rates and its
; tail lands at the head of the buffer. Hardware-confirmed: the transient is present in rate-3
; captures and ABSENT in rate-1 captures on the same build, and it replays identically at every
; loop wrap (r=0.83), so it is recorded data, not a playback event. Measured tail ~38ms at the
; buffer head => the chirp runs ~0.28s. Counts below hold the discard at 0.64-0.95s at every rate.
; S154: pre-roll shortened. It exists to discard the ~0.28s startup chirp (S70) and was held at
; 0.64-0.95s - two to three times longer than needed. Because it runs AFTER the second REC press,
; every bit of it is lost from the front of the take: speaking immediately after pressing REC loses
; the first word. 0.35s keeps a 25% margin over the measured chirp and halves the loss.
        LDY   #$044B            ; rate 1: 1099 samples = 0.35s
        LDA   SMPPRE
        CMPA  #$08
        BEQ   SMPRLDN
        LDY   #$07F1            ; rate 2: 2033 samples = 0.35s
        CMPA  #$04
        BEQ   SMPRLDN
        LDY   #$0E8D            ; rate 3: 3725 samples = 0.35s
        CMPA  #$02
        BEQ   SMPRLDN
        LDY   #$1532            ; S233e rate 4: 5426 samples = 0.35s at 15504 Hz
SMPRLDN
SMPC_PRE0
        LDB   SMPPRE            ; S49: prescale from param 1 (was hardcoded #$08)
SMPC_PRE0T
        SYNC
        LDA   $E20D             ; verified-tick pacing (S48; see main loop note)
        BITA  #$40
        BEQ   SMPC_PRE0T
        LDA   $E204
        DECB
        BNE   SMPC_PRE0T
        LDB   ,U                ; read + discard (advances the ADC, keeps the S/H tracking)
; --- input-filter CV keep-alive (pre-roll): the cutoff/preload DACs written at capture start are
;     sample-and-holds that droop over ~1-2s; the pre-roll alone is ~0.5s. Re-strobe them every 256
;     pre-roll samples (Y low byte hits 0) so recording starts at full brightness. Cheap common path
;     (TFR/TSTB/BNE ~5.5us) fits the inter-tick gap; the strobe itself rewrites the same DAC codes. ---
        TFR   Y,D
        TSTB
        BNE   SMPC_PRN
        LDA   INFVAL            ; S211: the param-3 value (extended load: +3 cycles, within margin)
        STA   $E417             ; re-park the CV mux on the input cutoff (cutoff ONLY - the preload
                                ; is a one-time preset; re-strobing it mid-capture both moves the
                                ; park off the cutoff and pumps the input operating point)
SMPC_PRN
        LEAY  -1,Y
        BNE   SMPC_PRE0
; S151: AUTO-TRIGGER WAITS HERE, after the pre-roll rather than before the capture. The pre-roll
; discards the ~0.28s startup chirp (S70) and is deliberately held at 0.64-0.95s at every rate - so
; triggering in the MAIN LOOP and only then entering SMPCAP put that whole window between the sound
; and the first stored byte. Measured on hardware with a five-word source: manual capture began at
; word "2" and auto at word "3", both about 0.6s late. A 0.5-1.0s percussion hit fits entirely inside
; that, which is why auto-trigger appeared to record silence.
; Waiting here means the chirp has already passed and storing begins on the sample that crosses the
; threshold - a latency of one sample instead of 0.6 seconds.
        TST   SMPAUT            ; S152: no PFIND here - X is the live DOC write pointer
        BEQ   SMPC_GO           ; manual -> store immediately, exactly as before
        LDD   #$FFFF
        STD   SMPWTC            ; bounded, so listening can never hang the machine
SMPC_WAIT
        LDB   SMPPRE
SMPC_WT2
        SYNC
        LDA   $E20D
        BITA  #$40              ; genuine T1 underflow - the same verified-tick pacing as capture
        BEQ   SMPC_WT2
        LDA   $E204
        DECB
        BNE   SMPC_WT2
        LDB   ,U                ; one input sample, paced at the capture rate
        SUBB  #$80              ; centre -> magnitude
        BPL   SMPC_WPOS
        NEGB
SMPC_WPOS
        CMPB  SMPTHR
        BCC   SMPC_GO           ; crossed -> begin storing on the very next sample
        LDD   SMPWTC
        SUBD  #$0001
        STD   SMPWTC
        BNE   SMPC_WAIT
SMPC_GO
        LDY   #$0080            ; arm the recording-loop CV refresh countdown (128 samples)
; S85: the N=1 fast capture path was REMOVED as dead code. SMPPRTAB is 8,4,2 - no rate uses N=1 -
;      and SMPCAP recomputes SMPPRE from param 1 (range 1-3) before this point, so the dispatch
;      could never take it. Reclaimed the bytes for the filter-calibration sweep.
SMPC_BYTE
        LDB   SMPPRE            ; S49: prescale = SMPPRTAB[param 1] timer ticks per stored sample
                                ; (was hardcoded #$08 - param 1 was decorative). Effective rate
                                ; 29.4kHz/N; SMPSHTAB keeps playback at unity pitch for every rate.
SMPC_PRE
        SYNC                    ; wait for an IRQ-line assertion
        LDA   $E20D             ; IFR - verified-tick pacing (S48): SYNC wakes on ANY assertion of
                                ; the shared line (DOC IRQ + DRQ + VIA), not just T1. Forensics on a
                                ; returned capture showed blind SYNC/ack ran ~10.9% fast with drift
                                ; and heavy inter-harmonic smear: spurious wakes counted as ticks.
        BITA  #$40              ; genuine Timer 1 underflow? (IFR flag sets independent of IER)
        BEQ   SMPC_PRE          ; no: spurious wake - ignore, keep waiting
        LDA   $E204             ; ack T1 (read counter low clears IFR bit 6)
        DECB
        BNE   SMPC_PRE          ; ...8 real ticks, letting the ADC conversion settle
        LDB   ,U                ; read the (now-settled) ADC sample ($ECE2)
        BNE   SMPC_NZ
        INCB                    ; force $00 -> $01 (oscillator halts on $00)
SMPC_NZ
        STB   ,X+               ; write the sample to RAM
; --- input-filter CV keep-alive (recording): without this, the input filter's cutoff/preload S&H
;     droops across the whole 8.9s BLOCKING capture (no main loop, no refresh), baking a brightness
;     ramp into the sample - which loop playback then turns into a periodic "filter modulation"
;     (measured: audio self-repeat r=0.95 at the loop period, brightness falling across each loop).
;     Re-strobe the same DAC codes every 128 stored samples (~35ms): sag between strobes is a couple
;     of percent of the droop constant. Worst-case added path ~20us fits inside the ~26us idle before
;     the next SYNC tick, so the 8-tick capture cadence is never disturbed. Y is free here (pre-roll
;     is done with it). ---
        LEAY  -1,Y
        BNE   SMPC_NR
        LDY   #$0080            ; next re-park in 128 samples
        LDA   INFVAL            ; S211: the param-3 value
        STA   $E417             ; re-park the CV mux on the input cutoff (cutoff ONLY - see setup
                                ; note; under the parking model this is pure insurance, since the
                                ; mux should already be sitting here for the whole capture)
SMPC_NR
        CMPX  #$8000            ; filled the 32768-sample buffer ($0000-$7FFF)?
        BCS   SMPC_BYTE
SMPC_DONE
; --- S71: LAND THE SAMPLE END ON A ZERO CROSSING ---
; When a held one-shot note runs out, the oscillator halts mid-waveform and that voice's analog
; sample-and-hold stays parked at whatever level the last played byte had. That DC step is Viz's
; "end transient" - measured as an abrupt full-amplitude stop with no spike, decaying over ~45ms as
; the coupling bleeds the offset away. The DOC never emits the byte it halts on (es5503.cpp: reads
; the byte, sees $00, calls halt_osc and skips the output entirely), so if the last byte that DOES
; play sits at the DC centre there is no step to thump. Scan the final 32 bytes of the buffer for
; the value closest to $80 and write the 8-zero halt marker immediately AFTER it.
; Scope: this stops the FREE-RUN one-shot path (rates 2-3). In SWAP mode a $00 byte hands over to
; the partner rather than stopping, so paged playback - rate 1 and every looped note - is unchanged
; until rate 1 moves to free-run. Costs at most 32 bytes of sample tail.
; DOC RAM is still mapped here; the port-B restore is further down.
        LDX   #$7FD8            ; candidate window $7FD8..$7FF7 (32 bytes, leaving room for 8 zeros)
        LDU   #$7FD8            ; best-so-far address (always valid: $FF seed below always loses)
        LDA   #$FF
        STA   ZCBEST
ZCSCAN
        LDA   ,X
        SUBA  #$80              ; signed distance from the DC centre
        BPL   ZCPOS
        NEGA                    ; |distance|  ($80 negates to itself: worst case, still correct)
ZCPOS
        CMPA  ZCBEST
        BCC   ZCNEXT            ; not closer (BCC = unsigned >=; this assembler has no BHS alias -
                                ; a BHS assembles to NOTHING, silently, per the S45 note above)
        STA   ZCBEST
        TFR   X,U               ; new best crossing
ZCNEXT
        LEAX  1,X
        CMPX  #$7FF8
        BCS   ZCSCAN
        TFR   U,X
        LEAX  1,X               ; marker goes AFTER the crossing byte so that byte still plays
        LDB   #$08
ZCMARK
        CLR   ,X+               ; 8 consecutive zeros = the DOC's halt marker
        DECB
        BNE   ZCMARK
; --- done: restore VIA Timer 1 to its boot value (the engine's envelope/LFO tick depends on it!),
;     then port B and interrupts. The boot runs Timer 1 free-running at $1770 (~333Hz) to pace
;     TICKALL; our capture ran it at the sample rate, so it MUST be put back or envelopes tick
;     ~88x too fast and notes go silent. ---
        LDA   SMPACRS
        STA   $E20B             ; restore ACR (free-run bit as boot had it)
        CLR   $E206
        CLR   $E207
        CLR   $E204
        CLR   $E205            ; S139: T1 = 0 -> PB7 = 500 kHz, exactly what stock writes and exactly
;                                what the schematic labels on the ACIA clock net. /16 gives 31250.
        LDA   #$40
        STA   $E20E             ; IER: disable Timer 1 interrupt (bit7=0 clears bit6)
        LDA   SMPPBSV
        STA   $E200             ; restore port B (bank 0, original mux)
        PULS  CC                ; restore CPU interrupt state
        CLR   SMPSTAT           ; back to idle
; --- close the input filter (channel 7) that capture opened, so it can't self-oscillate or drone in
;     the window before FREF's next pass re-establishes the voice filters. ---
        CLR   $E40F             ; input filter cutoff -> closed
        CLR   $E417             ; input filter resonance -> 0
        CLR   $E41F             ; input filter PRELOAD DAC -> cleared (matching what capture opened)
; --- resync FREF's filter write-on-change cache. Capture wrote the filter registers DIRECTLY
;     (silencing voice filters, opening the input filter) without going through FREF, so FREF's
;     cache (LFCUT/LFRES) is now stale vs the hardware. If we don't invalidate it, FREF may think a
;     value is already written and SKIP restoring it - leaving a filter stuck at capture's value
;     (self-oscillation drone / wrong cutoff / clicks). Force all 8 voices' caches to the $FF
;     sentinel so FREF rewrites the correct cutoff and resonance on the next pass. ---
; S219: capture-teardown LFCUT/LFRES invalidation loop DELETED (no reader since stock-exact refresh).
        JSR   SMPPLAY           ; switch oscillators to sample-mode config (resolution 4)
        CLR   SENDPOS           ; fresh capture overwrote the buffer -> forget any old end sentinel
        LDA   #$01
        STA   SMPRDY            ; mark sample present
        CLR   LPSCRB            ; S222b: new sample -> its capture marker needs scrubbing
        CLR   ROTPG             ; S226: fresh capture is unrotated by definition
        RTS

; Software prescaler per sample rate (rate 1..5): number of fixed-rate (~29.5kHz) timer ticks per
; stored sample. Effective rate = 29.5kHz / N. Gives long samples WITHOUT a 16-bit timer (which
; doesn't work reliably on this hardware). N: rate1=8(8.9s) 2=6(6.7s) 3=4(4.4s) 4=2(2.2s) 5=1(1.1s).
; ===== S233e: RATE 4 = 15503.9 Hz, LOCKED (build 183) =====
; 182's calibration disk (real middle C, rate-3 control 39.189 b/c = unchanged): all four N=1
; candidates LOCKED to exactly one sample per tick, steady across every take (<10 ppm of
; 2 MHz/T): T=129 -> 15503.8, 145 -> 13793.0, 161 -> 12422.4, 193 -> 10362.7 Hz. Free-run at
; T=65 vs lock at T=129: with ONE sample per tick the tick must be LONGER than the loop body
; (~115 cycles incl. DOC stalls; +14 on keep-alive passes). Rate 4 = T 129 (latch $7F):
; 1.512 x rate 3, ~2.11 s. Rates 1-3 keep their (N+1)-tick behaviour (mechanism unexplained).
; ===== S233d: 181 DID NOT LOCK (diagnostic build 182) =====
; Viz on 181: rate 4 repeatable but middle C plays 230.5 Hz, climbing = -219c = a true capture
; rate of ~17.46 kHz: N=1 at latch $3F STILL free-runs on the loop body (~114 cycles > the 65-cycle
; tick). The rates 1-3 '(N+1) ticks' law does not carry to N=1. 182 maps params 4-7 to N=1 at
; ticks of 129/145/161/193 cycles; a real-C calibration disk shows where pacing takes over.
; ===== S233c: CORRECTION + RATE 4 "LOCKED" (build 181 - see S233d: it was not) =====
; Viz's real middle C (tuner: 261.66 Hz) on build 180: rate 3 = 39.188 bytes/cycle -> 10254 Hz.
; The calibration sine used for S220b AND 179 was ~147 cents SHARP (C# + 47c = 284.8 Hz): every
; capture-rate figure in the docs was 8.86% LOW. With the true rates the law is exact at a
; 2.000 MHz E clock (MAME was right; the 1.837 MHz / 0.5444 us constant was an artefact):
;     period = (N+1) x (latch+2) x 0.5 us -> rate 1 3418.8 / rate 2 6349.2 / rate 3 10256.4 Hz
; Rate 4 at latch $2F free-ran on the loop body (~115 cycles): 17506 Hz (179) vs 17362 Hz
; drifting -0.3% across the take (180) - not repeatable. Viz chose the LOCKED option: latch $3F
; (the tick rates 1 and 3 already use, body < 2 ticks) with N=1 -> 2 ticks = 130 cycles =
; 15384.6 Hz exactly = 1.5 x rate 3. Tuning base by arithmetic (no measurement needed).
; ===== S233b: RATE 4 MEASURED = 16082 Hz (FIGURES BELOW ARE x(1/1.0886) - see S233c) (179 calibration disk: 61.470 bytes/cycle of a
; middle-C sine; rate-3 control 36.005 = unchanged). The prediction below FAILED: the period
; (62.18 us = ~114 E-cycles) is not a multiple of the 26.7 us tick - at this latch the loop is
; limited by its own body (incl. DOC stalls), not the timer. Viz accepted 16.1 kHz (1.71x rate
; 3, ~2.04 s). Kept: N=1, latch $2F (any tick shorter than the body gives the same rate).
; ===== S233: RATE 4 (calibration build 179) - original prediction =====
; Target 2 x C3 = 18839 Hz. Empirical capture law (fits rates 1-3 to <0.05% with ONE constant):
;     period = (N+1) x (latch+2) x 0.5444 us       (E ~ 1.837 MHz; one tick lost per sample)
; N=1, latch $2F (47): 2 x 49 x 0.5444 = 53.35 us -> ~18744 Hz predicted (-0.5%).
; Tick = 26.7 us, SHORTER than the ~31-45 us loop body: if the extra tick is "the tick that falls
; inside the body", the body now swallows exactly one tick (body < 2 ticks = 53.4 us) - same
; prediction. If instead nothing is lost at this latch, rate 4 lands at ~37.5 kHz; if two ticks
; are lost, ~12.5 kHz. The calibration disk (bytes/cycle of a known sine) settles which, and the
; DOC ADC (~31 us/conversion) caps any one-store-per-tick rate near 32 kHz anyway.
SMPPRTAB FCB  8,4,2,1           ; S233e: rate 4 = N 1, latch $7F (182 diagnostic). S233: rate 4 = N 1 (calibration build 179). S66: RATE 3 ADDED. The "unmodelable stall" is modelled after
;                                 all: per-sample time = (N+1) x (latch+2) x 0.5425us, i.e. the loop
;                                 loses exactly ONE tick per sample to its own post-tick code, and
;                                 the E clock is ~1.84MHz (NOT the 2MHz assumed since S53). Both
;                                 shipped rates fit to 0.4%: rate1 9x65x0.5425=317.4us vs 318.5
;                                 measured; rate2 5x63x0.5425=170.9us vs 172.1. So the ceiling was
;                                 never a hardware wall - rate 3 (N=2, same latch) predicts
;                                 3x65x0.5425=105.8us = ~9450Hz, 3x today's bandwidth.
;                                 Original S53 note follows.
;                                 S53 principled reset. Two measured fundamentals (returned-HFE
;                                 forensics + 3-octave playback test): (1) DOC bus arbitration
;                                 stretches E during capture's per-sample shared-bus accesses by a
;                                 stable ~10.3us/sample, so T1 "cycles" are slower in wall time -
;                                 ALL prior rates ran flat (rate-4 attempt: 22553Hz vs 29411; rate 1
;                                 ships ~64 cents flat). Fixed via SMPLTAB below.
;                                 (2) Playback rate scaling via freq-word shifts pushed words far
;                                 outside the proven 35-800 envelope; at shift 0 the DOC address
;                                 arithmetic wraps (played "octaves" measured at ratios 2.04 / 0.33).
;                                 Rate scaling now uses the RESOLUTION field (datasheet: "by using a
;                                 different pattern, octave shifting can be achieved"), words stay
;                                 shift-3. RES floors at 0 = one clean doubling from res 1, so rates
;                                 3-4 return only after this mechanism is hardware-validated.
SMPLTAB  FCB  $3F,$3D,$3F,$7F   ; S233e: rate 4 tick 129 cycles > the ~115-cycle loop body -> locked, 1 sample/tick = 2 MHz/129 = 15503.9 Hz. S233c: rate 4 latch $3F = rates 1/3's proven tick -> TIMER-PACED, 2 ticks/sample. per-rate T1 latch ($3F for rate 3: its tick, 35.3us, must stay
;                                 longer than the ~31-40us loop body or a SECOND tick is lost -
;                                 $3F is the value already proven stable at rate 1)
;                                 per-rate T1 latch, calibrated for the measured 10.34us/sample
;                                 stall: rate1 8x(65)x0.5+10.3=270.3us (3700Hz, +11 cents);
;                                 rate2 4x(63)x0.5+10.3=136.3us (7336Hz, -4 cents).
MWTGTAB  FCB  62,66,65,64      ; S155: wheel function 1-4 -> LFO speed, ->pitch, ->filter, ->amp
METTAB   FCB  $00,$08,$48,$49  ; S114: input level bars - none / bottom / bottom+middle / all three.
;                                 SEGTAB's bit order is a=0,b=1,c=2,d=3,e=4,f=5,g=6, so the three
;                                 horizontal segments are a ($01 top), g ($40 middle), d ($08 bottom).
; S230: LFO range rows for the SYNCP increment builder: {curve k, linear k, base16}.
LFORTAB FCB   35,16
        FDB   48                ; LOW:  64 .. 6978  (1.10x the original top)
        FCB   46,64
        FDB   5632              ; HIGH: 5696 .. 18997 (0.90x .. 3.00x)

TRIMBTB  FCB  47,40,95,60       ; S233e: rate 4 base 60 -> k 110 (unity 145.42 x (195/129)/2 = 109.91; +1.4c). S233c: rate 4 base 59 -> k 109 at param 6 = 50 (unity = 145.42 x 1.5 / 2 = 109.07 exactly: rate 4 = 3/2 x rate 3 by timer arithmetic; predicted -1c). S228: rate-1/2 bases RE-DERIVED from the S220b calibrated
;                                 capture rates. The S96 values (36,29) were slaved to the rate-3
;                                 ear anchor through the OLD rate beliefs - including the dead
;                                 10644 figure - which made rates 1-2 play ~208/~226 cents FLAT at
;                                 param 6 = 50 ever since (Viz's tuner measurements, S228: rate 2
;                                 at k=79 measured -226c => unity k=90.0; rate 1 unity = rate-3
;                                 unity x 2/3 exactly (C3=3*C1 byte-exact) = 145.42x2/3 = 96.95).
;                                 New bases: k at param-6=50 -> 97 / 90 / 145. Rate 3 keeps Viz's
;                                 accepted anchor (145, -5c). Predicted residuals: +1c / 0c / -5c.
;                                 NOTE: slots saved with param 6 compensating the old flat playback
;                                 now play sharp by the same amount - re-tune toward 50.
SMPRESTB FCB  $0A,$09,$09,$08   ; S233b: rate 4 = $08 = resshift 8 (one domain RIGHT of rates 2-3). Every SMPRES branch: $0A rate 1 / $09 rates 2-3 / $08 rate 4. S67: rate 3 res corrected $08 -> $09. Rate 3's real capture rate
;                                 is ~10644Hz = 1.83x rate 2, NOT the 2x that res 0 assumes, so res 0
;                                 put the sample's in-tune key an octave BELOW middle C (Viz: tuned
;                                 at C3 with param 6 = 83). res 1 halves the playback anchor, which
;                                 by exact algebra moves the in-tune key back to middle C with the
;                                 SAME trim value - derived from Viz's numbers, no rate estimate:
;                                 P(C4,res9,k) = 2W*k/128*2^-9 = W*k/128*2^-8 = P(C3,res8,k).
;                                 Original note: res 0 for rate 3 = 2x rate 2's playback.
;                                 Residual mismatch (real ratio 1.63, not 2) is absorbed by the
;                                 sample-tune param, as designed.
;                                 S54: res bumped +1 per rate = ONE OCTAVE DOWN playback anchor
;                                 (Viz: samples played one octave above the played key). Rate 2 now
;                                 lands exactly on the PROVEN res-1 config; rate 1 = res 2.
SMPSHTAB FCB  3,3,3,3           ; playback shift: ALWAYS 3 (the proven word envelope; rate
;                                 scaling lives in SMPRESTB, not the words)

; SMPPLAY: point all 16 oscillators at the recorded sample for playback.
; SMPPLAY: switch all 16 oscillators to SAMPLE-MODE playback config.
; wtptr=$00 (DOC $0000, where capture wrote); size=$3C (wavetblsize=7=32768 samples, RESOLUTION=4
; -> resshift=6). The higher resolution makes the playback frequency words ~16x larger for a given
; pitch, which gives enough numeric resolution to slow the sample down to its natural rate without
; the frequency quantizing to zero (the buzz/low-bass bug at resolution 0). Called after capture.
SMPPLAY
        CLRB
SMPPL1
        LDX   #$EC80
        CLR   B,X               ; wtptr = $00 -> DOC $0000 (recorded sample start)
        LDX   #$ECC0
        LDA   SMPRES            ; S53: per-rate size/res from SMPRESTB ($09 res1 proven / $08 res0 = 2x).
                                ; Original fixed value $09: wavetblsize=1 (512-byte pages), RESOLUTION=1. resshift =
                                ; resshifts[1]-1 = 10-1 = 9 - IDENTICAL to the old (res7,size7)=9, so the
                                ; freqtab, the /4096 total division, and the chromatic/no-buzz pitch are
                                ; all unchanged. Only the wrap point shrinks to 512 bytes, which makes the
                                ; wtptr page-granular (fine sample start) and drives swap-mode paging.
                                ; [former $3F comment: wavetblsize=7 (32768 samples), RESOLUTION=7 -
                                ; freq/512). Was res2 (freq/16) with a >>8 frequency shift - which
                                ; crushed the ~1144-count freqtab word down to single digits (2-7 over
                                ; the whole keyboard), quantizing pitch so hard that runs of adjacent
                                ; keys played the SAME pitch (confirmed by FFT of a hardware recording:
                                ; the note frequencies were exact integer multiples of one unit).
                                ; res7 divides 32x more in-chip, so the frequency shift drops to >>3
                                ; and the words become ~35-800: same pitch at every key (total division
                                ; unchanged at /4096), 32x finer pitch resolution - semitones resolve.
        STA   B,X
        STA   B,X
        INCB
        CMPB  #$10              ; all 16 oscillators
        BNE   SMPPL1
        RTS


; ============================================================
; BTNSCAN: read PARAM/VALUE/up/down. Active-low (pressed=0). Debounced.
;   PARAM = col4, VALUE = col6, up = col3, down = col5; all ROW2 (bit7).
; ============================================================
BTNSCAN
; up (col3)
        LDA   #$03
        JSR   SCANC
        ANDA  #$80
        BEQ   BUP
; down (col5)
        LDA   #$05
        JSR   SCANC
        ANDA  #$80
        BEQ   BDOWN
; PARAM (col4)
        LDA   #$04
        JSR   SCANC
        ANDA  #$80
        BEQ   BPARAM
; VALUE (col6)
        LDA   #$06
        JSR   SCANC
        ANDA  #$80
        BEQ   BVALUE
        CLR   BTNPREV           ; nothing pressed -> release latch
        RTS
BUP
        LDA   BTNPREV
        BEQ   BUPFIRST          ; first press
        DEC   RPTCTR            ; held: count down to next repeat
        BNE   BSDONE
        JSR   DOUP              ; repeat fire
        LDA   #$0B              ; repeat interval (faster: 14->11 ticks, ~30% faster)
        STA   RPTCTR
        BRA   BSDONE
BUPFIRST
        JSR   DOUP
        LDA   #$50              ; initial delay before auto-repeat begins
        STA   RPTCTR
        LDA   #$01
        STA   BTNPREV
        BRA   BSDONE
BDOWN
        LDA   BTNPREV
        BEQ   BDNFIRST
        DEC   RPTCTR
        BNE   BSDONE
        JSR   DODOWN
        LDA   #$0B              ; repeat interval (faster: 14->11 ticks, ~30% faster)
        STA   RPTCTR
        BRA   BSDONE
BDNFIRST
        JSR   DODOWN
        LDA   #$50              ; initial delay
        STA   RPTCTR
        LDA   #$01
        STA   BTNPREV
        BRA   BSDONE
BPARAM
        LDA   BTNPREV
        BNE   BSDONE
        CLR   DMODE             ; PARAM mode
        CLR   VTMR              ; explicit choice -> cancel temp value-display
        CLR   KPTMR             ; reset keypad entry (next digit starts fresh)
        LDA   #$01
        STA   BTNPREV
        BRA   BSDONE
BVALUE
        LDA   BTNPREV
        BNE   BSDONE
        LDA   #$01
        STA   DMODE             ; VALUE mode
        CLR   VTMR              ; explicit choice -> stays in value mode (no auto-revert)
        CLR   KPTMR             ; reset keypad entry (next digit starts fresh)
        STA   BTNPREV
BSDONE
        RTS

; DOUP: in PARAM mode step to next param; in VALUE mode increment value (clamp to max).
DOUP
        TST   DMODE
        BEQ   DUPARM
; VALUE mode: increment current value, clamp to max
        JSR   CURENT
        LDA   1,X               ; value
        CMPA  3,X               ; max
        BCC   DUEND             ; already >= max
        INCA
        STA   1,X
DUEND
        RTS
DUPARM
; PARAM mode: next param index (wrap)
        LDA   CURIDX
        INCA
        CMPA  #NPARM2
        BCS   DUPSET
        CLRA
DUPSET
        STA   CURIDX
        RTS

; DODOWN: PARAM mode prev param; VALUE mode decrement (clamp to min).
DODOWN
        TST   DMODE
        BEQ   DDPARM
        JSR   CURENT
        LDA   1,X
        CMPA  2,X               ; min
        BLS   DDEND
        DECA
        STA   1,X
DDEND
        RTS
DDPARM
        LDA   CURIDX
        BNE   DDDEC
        LDA   #NPARM2
DDDEC
        DECA
        STA   CURIDX
        RTS

; SCANC: A=column. Write ($18|col), settle, return A=row sense.
SCANC
        ORA   #$18
        STA   $E20F
        LDB   #$10
SCCDLY  DECB
        BNE   SCCDLY
        LDA   $E20F
        RTS

; ============================================================
; KPSCAN: numeric keypad direct entry. Scans the 10 digit keys (matrix: ROW1=bit6, ROW2=bit7,
; columns via SCANC). On a fresh press, applies the digit to the current param value. KPTAB holds
; {column, rowmask} per digit ordered 0..9, so the loop index IS the digit value.
; ============================================================
KPSCAN
        LDU   #KPTAB
        CLRB                    ; B = digit 0..9
KPKLOOP
        PSHS  B
        LDA   ,U                ; column
        JSR   SCANC             ; A = row bits (clobbers A,B)
        ANDA  1,U               ; mask (bit6=ROW1 or bit7=ROW2)
        BEQ   KPKHIT            ; active-low: 0 = pressed
        PULS  B
        INCB
        LEAU  2,U
        CMPB  #10
        BNE   KPKLOOP
        CLR   KPPREV            ; no digit down -> release debounce latch
        RTS
KPKHIT
        PULS  B                 ; B = digit
        STB   KPDIG
        LDA   KPPREV
        BNE   KPKRET            ; already handled this press
        LDA   #$01
        STA   KPPREV
        LDA   SLOTMODE
        BEQ   KPKNORM
        LDA   KPDIG             ; slot mode: digit selects the slot (0-9)
        STA   SLOTNUM
        BRA   KPKRET
KPKNORM
        JSR   KPAPPLY
KPKRET
        RTS

; KPAPPLY: apply KPDIG to the current param. Fresh (value = digit) unless the keypad timer is still
; running on the SAME param, in which case append (value*10 + digit). Clamped to [min,max]. Shows the
; value (DMODE=1) and re-arms the timers.
KPAPPLY
; keypad = parameter selection ONLY. Accumulate a 2-digit number and jump to the param whose number
; matches. The value is never touched here, and the view mode (DMODE) is left alone: the display shows
; the number while typing, then reverts to whatever view was active (param number or value).
        TST   KPTMR
        BEQ   KPAFR             ; timer idle -> fresh entry
        LDA   KPACC
        CMPA  #10
        BHS   KPAFR             ; already 2 digits -> restart fresh
        LDB   #10
        MUL                     ; A=KPACC(<10), B=10 -> D=KPACC*10 (hi=0)
        ADDB  KPDIG
        STB   KPACC             ; KPACC = KPACC*10 + digit
        BRA   KPADN
KPAFR
        LDB   KPDIG
        STB   KPACC             ; fresh: KPACC = digit
KPADN
        LDA   #VTMOUT
        STA   KPTMR             ; inter-digit window + "show KPACC" while typing
; find the param whose spec number == KPACC and jump to it
        LDX   #PARMTAB
        CLRA                    ; index 0
KPAPL
        LDB   ,X                ; spec number of this entry
        CMPB  KPACC
        BEQ   KPAPH             ; match -> A = its index
        LEAX  4,X               ; next {spec,value,min,max}
        INCA
        CMPA  #NPARM2
        BNE   KPAPL
        RTS                     ; no such param -> leave the current selection (number shown briefly)
KPAPH
        STA   CURIDX            ; jump to that param
        RTS

; KPTAB: {column, rowmask} per digit 0..9. rowmask $40 = ROW1 (bit6), $80 = ROW2 (bit7).
KPTAB
        FCB   5,$40             ; 0
        FCB   0,$80             ; 1
        FCB   6,$40             ; 2
        FCB   0,$40             ; 3
        FCB   1,$80             ; 4
        FCB   3,$40             ; 5
        FCB   1,$40             ; 6
        FCB   2,$80             ; 7
        FCB   4,$40             ; 8
        FCB   2,$40             ; 9


FONT
        FCB   $3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F

; 256-byte signed sine table for boot-time wave generation (-127..127 as two's complement).
; S113: the 256-byte sine table is gone with the additive generator that used it.
RATE16TAB
        FDB   $FF00,$F078,$E2C4,$D5D8,$C9A9,$BE2B,$B355,$A91D
        FDB   $9F7A,$9664,$8DD2,$85BD,$7E1E,$76EF,$7028,$69C4
        FDB   $63BD,$5E0E,$58B2,$53A4,$4EE0,$4A61,$4624,$4225
        FDB   $3E60,$3AD2,$3778,$344F,$3154,$2E85,$2BDE,$295E
        FDB   $2703,$24CA,$22B1,$20B7,$1EDA,$1D18,$1B6F,$19DF
        FDB   $1866,$1702,$15B2,$1476,$134B,$1232,$1128,$102E
        FDB   $0F42,$0E63,$0D92,$0CCC,$0C11,$0B61,$0ABB,$0A1E
        FDB   $098B,$0900,$087C,$0801,$078C,$071E,$06B6,$0654
        FDB   $05F8,$05A1,$054F,$0501,$04B8,$0473,$0432,$03F5
        FDB   $03BB,$0385,$0352,$0321,$02F4,$02C9,$02A0,$027A
        FDB   $0256,$0234,$0213,$01F5,$01D9,$01BE,$01A4,$018C
        FDB   $0176,$0160,$014C,$0139,$0128,$0117,$0107,$00F8
        FDB   $00EA,$00DC,$00D0,$00C4

; ============================================================
; PITTICK: pitch-envelope ADSR (8-bit level OPLV), current voice U. State OPST:
;   0=idle 1=attack 2=decay 3=sustain 4=release. Uses A only (preserves B/X/U).
; ============================================================
PITTICK
        LDA   OPST,U
        BEQ   PTEND
        CMPA  #$01
        BEQ   PTATK
        CMPA  #$02
        BEQ   PTDEC
        CMPA  #$03
        BEQ   PTSUS
        CMPA  #$04
        BEQ   PTREL
PTEND
        RTS
PTATK
        LDA   OPLV,U
        ADDA  PATKR
        BCS   PTATSAT           ; past 255 -> peak reached
        STA   OPLV,U
        RTS
PTATSAT
        LDA   #$FF
        STA   OPLV,U
        LDA   #$02
        STA   OPST,U            ; -> decay
        RTS
PTDEC
        LDA   OPLV,U
        SUBA  PDECR
        BCS   PTDECHIT          ; past 0 -> sustain
        CMPA  PSUSL
        BLS   PTDECHIT          ; reached sustain
        STA   OPLV,U
        RTS
PTDECHIT
        LDA   PSUSL
        STA   OPLV,U
        LDA   #$03
        STA   OPST,U            ; -> sustain
        RTS
PTSUS
        LDA   PSUSL
        STA   OPLV,U            ; hold
        RTS
PTREL
        LDA   OPLV,U
        SUBA  PRELR
        BCS   PTRELDN           ; past 0 -> done
        STA   OPLV,U
        RTS
PTRELDN
        CLR   OPLV,U
        CLR   OPST,U            ; -> idle
        RTS

; ============================================================
; KTRKOFF: keyboard-tracking cutoff offset for the current voice (U). Returns signed 16-bit in D.
;   offset = KTRACK * (OKEY - 22) >> 3   (KTRACK = param23-49; middle C key = 22). 0 if either is 0.
; ============================================================
KTRKOFF
        LDA   KTRACK
        BNE   KTRK1
KTRKZ
        CLRA
        CLRB
        RTS
KTRK1
        LDB   OKEY,U
        SUBB  #22               ; B = note offset from middle C (signed)
        BEQ   KTRKZ
        CLR   KTSGN             ; combined sign flag (0 = positive)
        TSTA
        BPL   KTRKA
        NEGA                    ; |KTRACK|
        COM   KTSGN
KTRKA
        TSTB
        BPL   KTRKB
        NEGB                    ; |note offset|
        COM   KTSGN
KTRKB
        MUL                     ; D = |KTRACK| * |note offset|
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D >>= 3
        TST   KTSGN
        BEQ   KTRKRET           ; positive -> done
        COMA
        COMB
        ADDD  #$0001            ; negate (two's complement)
KTRKRET
        RTS

; ============================================================
; TPSCAN: Sample Upper / Sample Lower -> octave transpose (keyboard; MIDI when it exists).
;   Upper (ROW0/bit5, col2) = +1 octave (max +2); Lower (col7) = -1 octave (min -2); both = reset 0.
;   Fires once on a fresh press (debounced via TSPPREV). Uses A,B (SCANC clobbers them); preserves X,U.
; ============================================================
TPSCAN
        LDA   #2
        JSR   SCANC             ; column 2 = Sample Upper
        ANDA  #$20              ; ROW0 (bit5); 0 = pressed
        STA   TPUTMP            ; save it: SCANC clobbers B, so the mask can't accumulate in B
        LDA   #7
        JSR   SCANC             ; column 7 = Sample Lower
        ANDA  #$20              ; A = 0 if lower pressed
        CLRB                    ; build mask now (no more SCANC to clobber B)
        TSTA
        BNE   TPCKU
        ORB   #$02              ; lower pressed
TPCKU
        TST   TPUTMP
        BNE   TPACT
        ORB   #$01              ; upper pressed
TPACT
        TSTB
        BEQ   TPREL             ; nothing pressed -> release the latch
        LDA   TSPPREV
        BNE   TPRET             ; already handled this press -> wait for release
        LDA   #$01
        STA   TSPPREV
        CMPB  #$03
        BEQ   TPRST             ; both -> reset transpose to 0
        CMPB  #$02
        BEQ   TPDN              ; lower only -> down
; upper only -> up one octave, clamp to +24
        LDA   TRANSPOSE
        ADDA  #12
        CMPA  #24
        BLE   TPPUT
        LDA   #24
        BRA   TPPUT
TPDN
; down one octave, clamp to -24
        LDA   TRANSPOSE
        SUBA  #12
        CMPA  #-24
        BGE   TPPUT
        LDA   #-24
TPPUT
        STA   TRANSPOSE
        RTS
TPRST
        CLR   TRANSPOSE
        RTS
TPREL
        CLR   TSPPREV
TPRET
        RTS

; ============================================================
; PBUILD: (re)initialize PARMTAB with every parameter default. Called at boot and by the
; Load Upper + Load Lower panel-reset. SYNCP re-reads PARMTAB each pass, so the engine follows.
; ============================================================
PBUILD
        LDX   #PARMTAB
; S210: the FULL renumbered table (claude_PARAM_MAP.md is the reference). Regenerated from the
; unified142 image's extracted {spec,value,min,max} quadruples, so every default/min/max survived
; the renumbering byte-for-byte. 47 entries here, in numeric order (the display walks the table);
; the control/MIDI group (71-75) is appended by MINIT so LPSCAN's reset-all leaves it alone.
        LDD   #$0103            ; 1 - sample rate (default 3)
        STD   ,X++
        LDD   #$0104            ; min 1, max 4 (S233: rate 4)
        STD   ,X++
        LDD   #$0201            ; 2 - input source (0=mic 1=line) (default 1)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$0363            ; 3 - input filter frequency (default 99)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$0400            ; 4 - trigger mode (0=manual 1=auto) (default 0)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$0514            ; 5 - auto-trigger threshold (default 20)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$0632            ; 6 - sample tune (default 50)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$073C            ; 7 - base note (default 60)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$0818            ; 8 - coarse tune (24=zero) (default 24)
        STD   ,X++
        LDD   #$0030            ; min 0, max 48
        STD   ,X++
        LDD   #$0931            ; 9 - fine tune (49=zero) (default 49)
        STD   ,X++
        LDD   #$0062            ; min 0, max 98
        STD   ,X++
        LDD   #$0A00            ; 10 - detune mix (0=off) (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$0B0B            ; 11 - detune amount (10=unison) (default 11)
        STD   ,X++
        LDD   #$0014            ; min 0, max 20
        STD   ,X++
        LDD   #$0C00            ; 12 - detune drift depth (default 0)
        STD   ,X++
        LDD   #$0004            ; min 0, max 4
        STD   ,X++
        LDD   #$0D01            ; 13 - loop mode (0=off 1=on) (default 1)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$0E00            ; 14 - playback direction (0=fwd 1=rev) (default 0)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$0F00            ; 15 - sample start (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1063            ; 16 - sample end (default 99)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1100            ; 17 - loop start (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1263            ; 18 - loop end (default 99)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1563            ; 21 - cutoff (default 99)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1614            ; 22 - resonance (default 20)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1731            ; 23 - keyboard tracking (49=off) (default 49)
        STD   ,X++
        LDD   #$0062            ; min 0, max 98
        STD   ,X++
        LDD   #$1800            ; 24 - velocity -> filter depth (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1900            ; 25 - velocity -> resonance depth [NEW S210] (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$1F00            ; 31 - amp attack (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2028            ; 32 - amp decay (default 40)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2132            ; 33 - amp sustain (default 50)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$221E            ; 34 - amp release (default 30)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2363            ; 35 - velocity -> amp depth (default 99)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2900            ; 41 - filter attack (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2A28            ; 42 - filter decay (default 40)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2B32            ; 43 - filter sustain (default 50)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2C14            ; 44 - filter release (default 20)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$2D31            ; 45 - filter env depth (49=zero) (default 49)
        STD   ,X++
        LDD   #$0062            ; min 0, max 98
        STD   ,X++
        LDD   #$2E31            ; 46 - filter env -> resonance depth (49=zero) [NEW S210] (default 49)
        STD   ,X++
        LDD   #$0062            ; min 0, max 98
        STD   ,X++
        LDD   #$3300            ; 51 - pitch env attack (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$3414            ; 52 - pitch env decay (default 20)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$3500            ; 53 - pitch env sustain (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$360A            ; 54 - pitch env release (default 10)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$3700            ; 55 - pitch env depth magnitude (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$3801            ; 56 - pitch env direction (0=dn 1=up) (default 1)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$3D00            ; 61 - LFO waveform (0=tri 1=saw+ 2=saw- 3=sq 4=rand) (default 0)
        STD   ,X++
        LDD   #$0004            ; min 0, max 4
        STD   ,X++
        LDD   #$3E04            ; 62 - LFO speed (default 4)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$3F00            ; 63 - LFO trigger (0=retrig 1=free) (default 0)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$4000            ; 64 - LFO -> amp depth (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$4100            ; 65 - LFO -> filter depth (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$4200            ; 66 - LFO -> pitch depth (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
        LDD   #$4300            ; 67 - LFO -> resonance depth [NEW S210] (default 0)
        STD   ,X++
        LDD   #$0063            ; min 0, max 99
        STD   ,X++
; S230b: the LFO RANGE (76) sits at the END of the table (after the 71-75 control group)
; for v3-header compatibility, but it is a SOUND param - reset-all must reset it to LOW
; (Viz). Writing it here puts it under PBUILD's reset umbrella; the control group between
; stays untouched. MINIT's boot-time append writes the same bytes - deliberate double
; cover, and the post-build table audit keeps the two in step.
        LDX   #PARMTAB+(NPARM2-2)*4  ; S232: 76 is now second-to-last (77 follows, NOT reset)
        LDD   #$4C00            ; 76 - LFO range (default 0 = low)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        RTS

; ============================================================
; LPSCAN: Load Upper (ROW0/bit5, col0) + Load Lower (col1) pressed together -> reset all params.
;   Re-runs PBUILD (all defaults); SYNCP re-reads PARMTAB next pass. Sample in RAM and the octave
;   transpose are left untouched. Debounced via LPPREV. Uses A,B; preserves X,U.
; ============================================================
LPSCAN
        CLRA
        JSR   SCANC             ; column 0 = Load Upper
        ANDA  #$20              ; ROW0 (bit5)
        BNE   LPREL             ; upper not pressed -> not the combo
        LDA   #1
        JSR   SCANC             ; column 1 = Load Lower
        ANDA  #$20
        BNE   LPREL             ; lower not pressed -> not the combo
        LDA   LPPREV
        BNE   LPRET             ; already handled this press
        LDA   #$01
        STA   LPPREV
        JSR   PBUILD            ; reload all parameter defaults
        RTS
LPREL
        CLR   LPPREV
LPRET
        RTS

; ============================================================
; PATCH SAVE / LOAD (single sector, track PTRACK, using the stock ROM disk routines).
; Requires DP=$E8 for the ROM routines; motor on; verify-seek; then read/write one sector.
; Param block: $8002=track, $8003=sector, $8004/5=buffer, $8006=result. NMI ($F0B0) terminates each op.
; Buffer layout: [magic $A5 $5A][PARMTAB, NPARM*4 bytes][pad].
; ============================================================
; S85: DKSAVE / DKLOAD REMOVED as dead code. These were the original patch-only (PARMTAB)
; disk routines, superseded by the slot save/load path; nothing has called either since.
; Reclaimed for the filter-calibration sweep.


; LSSCAN: Load Seq (col4) -> DKLOAD ; Save Seq (col5) -> DKSAVE. ROW0/bit5, debounced. Uses A,B; keeps X,U.
LSSCAN
        LDA   #4
        JSR   SCANC             ; column 4 = Load Seq
        ANDA  #$20              ; ROW0 (bit5); 0 = pressed
        STA   LSTMP             ; save (SCANC clobbers B; build state after both scans)
        LDA   #5
        JSR   SCANC             ; column 5 = Save Seq
        ANDA  #$20              ; A = 0 if Save pressed
        TST   LSTMP
        BNE   LSCKS             ; Load not pressed -> check Save
        LDB   LSPREV
        BNE   LSRET             ; already handled this press
        LDA   #$01
        STA   LSPREV
        LDA   #$02
        STA   SLOTMODE          ; Load Seq -> load-pending, pick slot then Enter
        RTS
LSCKS
        TSTA
        BNE   LSREL             ; Save not pressed either -> release latch
        LDB   LSPREV
        BNE   LSRET
        LDA   #$01
        STA   LSPREV
        LDA   #$01
        STA   SLOTMODE          ; Save Seq -> save-pending, pick slot then Enter
        RTS
LSREL
        CLR   LSPREV
LSRET
        RTS

; ===== PSSCAN (S209): PANIC - Play Seq pressed TWICE within ~0.7s silences everything =====
; Play Seq = panel column 3, ROW0/bit5 (keypad schematic: the sequencer row Load/Save/Rec Seq live
; on; cross-checked against every column this OS already scans). Orovela has no sequencer, so the
; button is free. Double-press guards against accidental hits mid-performance.
; The kill is GRACEFUL: every active voice's amp/filter/pitch envelopes are forced into release
; (state 4) - including pedal-parked state-5 voices - so hung notes fade at the patch's release rate
; with no click. SUSTAIN and the keyboard/MIDI parser scratch states are cleared too: a hung note
; usually means a lost note-off left something desynced, and this resyncs all of it.
; Uses A,B (SCANC clobbers B); preserves X,U (the voice walk saves/restores them).
PSSCAN
        TST   PSTMR
        BEQ   PSSC0
        DEC   PSTMR             ; the double-press window counts down every pass (~9ms)
PSSC0
        LDA   #3
        JSR   SCANC             ; column 3
        ANDA  #$20              ; ROW0 (bit5); 0 = Play Seq pressed
        BEQ   PSDN
        CLR   PSPREV            ; released -> re-arm the edge detector
        RTS
PSDN
        LDA   PSPREV
        BNE   PSRET             ; held over from the last pass -> not a new press
        LDA   #$01
        STA   PSPREV
        LDA   PSTMR
        BNE   PANIC             ; second press inside the window -> kill
        LDA   #80               ; first press: open a ~0.7s window (80 passes)
        STA   PSTMR
PSRET
        RTS
PANIC
        CLR   PSTMR
        CLR   SUSTAIN           ; nothing re-parks in the pedal-hold state
        CLR   KBST              ; resync the local keyboard note state machine
        CLR   MISTAT            ; drop MIDI running status; the next status byte resyncs the parser
        CLR   MICNT
        PSHS  B,U
        LDU   #VBASE
        CLRB
PANLP
        LDA   OACT,U
        BEQ   PANNX             ; inactive voice -> leave it
        LDA   #$04
        STA   OAST,U            ; amp -> release (covers state-5 pedal holds too)
        STA   OFST,U            ; filter -> release
        STA   OPST,U            ; pitch -> release
PANNX
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   PANLP
        PULS  B,U
        RTS

; SLOTSRV: while a slot is being picked, Enter (col7 ROW1) runs the save/load, Cancel (col7 ROW2) aborts.
SLOTSRV
; S115: CANCEL while ARMED disarms and returns to the parameter view. This was described as the
; workflow but never actually implemented - the armed state could only be left by recording.
        LDA   SMPSTAT
        CMPA  #$01
        BNE   SLNOARM
        LDA   #7
        JSR   SCANC
        ANDA  #$80              ; Cancel = ROW2, active-low
        BNE   SLNOARM           ; not pressed
        CLR   SMPSTAT           ; disarm -> the meter disappears, digits return
        CLR   METPK
        CLR   $E417             ; S119: close the input filter again
        CLR   $E40F
        LDA   METPB
        STA   $E200             ; S122: restore port B - the wheels need their mux back
; S121: FREF was suspended while armed, so its write-on-change caches no longer describe the DACs.
; Invalidate them so every channel is re-driven on the next pass.
; S219: SMDINV cache-invalidation body DELETED (no reader); callers get a plain RTS.
        RTS
SLNOARM
        LDA   SLOTMODE
        BEQ   SLSRET            ; not picking -> nothing to do
        LDA   #7
        JSR   SCANC             ; column 7
        ANDA  #$40              ; Enter = ROW1 ($40), active-low
        STA   SLTMP             ; save (SCANC clobbers B, and we scan again)
        LDA   #7
        JSR   SCANC
        ANDA  #$80              ; Cancel = ROW2 ($80), active-low  -> A
        TST   SLTMP
        BNE   SLCKC             ; Enter not pressed -> check Cancel
        LDB   SLTPREV
        BNE   SLSRET            ; already handled this press
        LDA   #$01
        STA   SLTPREV
        JSR   SLOTEXE           ; Enter -> run it
        RTS
SLCKC
        TSTA
        BNE   SLREL             ; Cancel not pressed -> release latch
        LDB   SLTPREV
        BNE   SLSRET
        LDA   #$01
        STA   SLTPREV
        CLR   SLOTMODE          ; Cancel -> back to normal
        RTS
SLREL
        CLR   SLTPREV
SLSRET
        RTS

; SLOTEXE: run the pending save or load for UNIFIED slot SLOTNUM (base track 11+6*slot).
; Save = params always + the 32KB sample when one is present (SMPRDY). Load (build L1) restores
; params always + the sample when the slot header says one is there (flags bit0). Old patch-only
; slots at tracks 20-29 remain obsolete/unwired.
SLOTEXE
        LDA   SLOTNUM
        LDB   #6
        MUL                     ; D = slot*6 (fits in B: max 54)
        ADDB  #11
        STB   SLTRK             ; slot base track = 11 + 6*slot (slots 0-9 -> tracks 11-70)
        LDB   SLOTMODE          ; 1=save, 2=load
        CLR   SLOTMODE          ; leave slot mode before the (blocking) op
        CMPB  #$01
        BNE   SLEXLD
        JSR   SMSAVE2
        RTS
SLEXLD
        JSR   SMLOAD2            ; L1: unified load (params + sample, header-gated)
        RTS

; DKREVIA: after a disk op, restart our ~333Hz envelope-tick timer (F15D zeroed T1) and restore DP=$80.
; F15D already left ACR/PCR/DDRA at the values our runtime uses, so only T1 + DP need fixing.
DKREVIA
        ANDCC #$BF              ; S127: disk session over - MIDI receive back on
        LDA   SVACR
        STA   $E20B             ; restore our VIA state
        LDA   SVPCR
        STA   $E20C
        LDA   SVDDRA
        STA   $E203
        LDA   SVPORTB
        STA   $E200
        JSR   TREST             ; restore T1=$001E (MIDI clock) + T2=$1770 (envelope tick)
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP                     ; 7 NOPs keep DKREVIA byte-length identical to the T1-load it replaced
; invalidate the per-voice filter DAC cache (LFCUT+LFRES, 16 contiguous bytes) so FREF re-strobes every
; cutoff/resonance next passes - recharges the CEM3328 S&H that drooped during the disk-op block.
        LDX   #LFCUT
        LDA   #$FF
        LDB   #16
DKINVLF
        STA   ,X+
        DECB
        BNE   DKINVLF
        LDA   #$80
        TFR   A,DP
; re-prime the keyboard serial (the disk op's VIA reconfig can stall the SR handshake; the boot
; primes it the same way). Without this, key presses may stop registering -> no notes -> no sound.
        JSR   CA2ACK
        LDA   $E20A
        JSR   CA2ACK
        RTS

; DKSETUP: put the VIA in disk mode + reset the FDC, exactly like the boot ROM's $F15D BUT WITHOUT its
; DOC reset ($ECE1 clear + $EC00-$ECDF clear + $F1BB) which would silence the synth. Sets DP=$E8.
DKSETUP
; S127: mask FIRQ for the whole disk session. The inner critical sections already use ORCC #$50
; (I and F), but a MIDI byte arriving BETWEEN them would run the receive handler mid-transfer. This
; project has lost builds to stray interrupts during 32-sector transfers, so receive stays off until
; DKREVIA. Bytes are dropped rather than queued during a save or load - far better than a corrupt
; transfer, and a sequencer will not be mid-phrase while you are saving.
        ORCC  #$40              ; F: no MIDI receive while the disk is in use
        LDA   $E20B
        STA   SVACR             ; save our VIA state to restore after the op
        LDA   $E20C
        STA   SVPCR
        LDA   $E203
        STA   SVDDRA
        LDA   $E200
        STA   SVPORTB
        LDA   #$30              ; port B value: motor off, bank 0
        LBRA  DKCOM             ; S226R: rest shared with DKSETM (was a near-duplicate)

; ============================================================
; UNIFIED SLOT SAVE (build S1). Writes the current patch + (if SMPRDY) the 32KB sample to slot
; tracks SLTRK..SLTRK+5. Order: sample sectors FIRST, header LAST (an interrupted save can never
; leave a valid header pointing at half-written audio; load will magic-fail = empty slot).
; DOC-RAM reads during the FDC write loop only DELAY the FDC, which it tolerates (proven: the
; smpdrain-era save side). Oscillators are halted + OIR drained first so a looping sample's
; page-swap IRQs can't falsely release SYNC and desync the transfer (TECHNICAL_FINDINGS 5.2).
; Oscillators are NOT un-halted afterward: note-on rewrites every control reg anyway.
; ============================================================
; ---- [reclaimed] old SMSAVE body ($B008-$B0D0, 201 bytes) deleted: superseded by SMSAVE2.
; ---- Live helpers PSEGL/HDRPACK/OSCHALT/OIRDRAIN/SMTAB below are kept (called by the block).
PSEGL
        ORA   #$18              ; column select, anodes off (active-low)
        ANDA  #$F7              ; left anode on
        STA   $E20F
        RTS


; HDRPACK: build the 193-byte slot header in PATCHBUF.
; [0]=$C3 [1]=$3C (NEW magic - old $A5$5A patch slots can never be misparsed as unified slots)
; [2]=version $03  [3]=flags (bit0 = has sample)
; [4..183]=PARMTAB (45*4)  [184..192]=SMPSHFT,SMPPRE,SSTART,SENDPOS,SENDSAV,LMODE,LSTART,SENDPG,ENDPG
; [193..200]=SENDSV8
; S88 VERSION 3: the param block now carries ALL 45 entries instead of the first 43. Entries #43
; (MIDI channel) and #44 (SAMPLE TUNE) were being left out, so sample tune reset to 50 on every
; power cycle and each loaded slot had to be re-tuned by ear - the round-trip in S55 only appeared
; to pass because save and load happened in one session with the values still live in RAM.
; The metadata simply moves 8 bytes later; the header sector is 512 bytes and now uses 201.
; Version 2 slots still load: the reader picks the length from the version byte.
; [185..192]=SENDSV8 (v2 layout, for reference) (the 8 sample bytes saved under the end marker) -> the end-sentinel state
; round-trips exactly; the buffer is saved verbatim WITH its marker zeros in place.
HDRPACK
        LDX   #PATCHBUF
        LDA   #$C3
        STA   ,X+
        LDA   #$3C
        STA   ,X+
        LDA   #$05              ; S232: version 5 = 54-entry param block (+param 77).
        STA   ,X+               ; v3 (sample manager) and v4 (1.2) slots still load - see SMLOAD
        LDA   SMPRDY
        STA   ,X+               ; flags: bit0 = sample present
        LDY   #PARMTAB
        LDB   #NPARM2*4         ; S88: 180 bytes = all 45 entries (was NPARM*4 = 172, which dropped
                                ; the MIDI channel and the sample tune). The metadata that follows is
                                ; written with ,X+ so it shifts along automatically.
HPCP1
        LDA   ,Y+
        STA   ,X+
        DECB
        BNE   HPCP1
        LDA   SMPSHFT
        STA   ,X+
        LDA   SMPPRE
        STA   ,X+
        LDA   SSTART
        STA   ,X+
        LDA   SENDPOS
        STA   ,X+
        LDA   SENDSAV
        STA   ,X+
        LDA   LMODE
        STA   ,X+
        LDA   LSTART
        STA   ,X+
        LDA   SENDPG
        STA   ,X+
        LDA   ENDPG
        STA   ,X+
        LDY   #SENDSV8
        LDB   #8
HPCP2
        LDA   ,Y+
        STA   ,X+
        DECB
        BNE   HPCP2
        RTS

; OSCHALT: halt all 16 oscillators by WRITING a fixed control value ($01 = halt, free-run, ch0,
; IRQ disabled). No register READ-BACK - the boot ROM's own $F1BB halts oscillators the same way
; (fixed-value writes) and note-on rewrites every control register anyway.
OSCHALT
        LDX   #$ECA0
        LDB   #$01              ; oscillators 1-15 only; osc 0 stays running (OSC0RUN)
OHLP
        TFR   B,A
        LSRA                    ; A = osc>>1 = voice/channel
        ASLA
        ASLA
        ASLA
        ASLA                    ; A = channel<<4
        ORA   #$01              ; + halt: EXACTLY the engine's init/idle contract for this osc
        STA   B,X
        INCB
        CMPB  #$10
        BNE   OHLP
        RTS

; OIRDRAIN: drain the OIR using the boot ROM's exact idiom ($F1D3): 32 unconditional reads of
; $ECE0 with the ROM's own delay between them. Silicon-proven at every boot; no bit tests.
OIRDRAIN
        LDB   #$20
ODLP
        LDA   $ECE0
        LDY   #$000C
        JSR   $F0A7             ; ROM delay loop (counts Y down)
        DECB
        BNE   ODLP
        RTS

; SMTAB: the 34 (rel-track, sector) pairs of a slot's sample region, in track order.
; Tracks 0-3 use all 6 sectors (5632B each), tracks 4-5 use sectors 0-4 (5120B each) = 32768 exactly.
; Sector 5 of rel-track 4 is the header; sector 5 of rel-track 5 is spare.
SMTAB
        FCB   0,0,0,1,0,2,0,3,0,4,0,5
        FCB   1,0,1,1,1,2,1,3,1,4,1,5
        FCB   2,0,2,1,2,2,2,3,2,4,2,5
        FCB   3,0,3,1,3,2,3,3,3,4,3,5
        FCB   4,0,4,1,4,2,4,3,4,4
        FCB   5,0,5,1,5,2,5,3,5,4

; ============================================================
; UNIFIED SLOT LOAD (build L1) - the other half of the S10 unified save.
; Reads slot SLTRK's header (SLTRK+4, sec5); magic/version-gated so an empty or foreign
; slot aborts with NO state change. Restores PARMTAB (SYNCP re-reads it next main-loop
; pass). If flags bit0 (has-sample): reads the 34 sample sectors ONE DISK SESSION EACH
; into PATCHBUF (main RAM) and copies each into the DOC window $0000-$7FFF in the NORMAL
; machine state (post-DKREVIA) with osc 0 running - TECHNICAL_FINDINGS 5.3-5.6: DOC-RAM
; CPU writes only land fully torn down, never streamed from the FDC (5.4), never with all
; oscillators halted (5.3/5.5). The decisive smpramp test (5.6) proved a post-DKREVIA CPU
; fill of the whole window lands cleanly with osc 0 un-halted, in a post-reboot context.
; Each session is the proven DKLOAD/S10 single-op shape: DKSETUP / params-after / motor
; on / verify-seek / read / status-read / motor off / DKREVIA. The ROM motor-on's fixed
; spin-up (Y=$FFFF delay = ~0.5s at the 2MHz E-clock) runs once per session, so a full
; sample load takes roughly 30s; the rotating left-digit segment (one step per sector)
; shows progress and distinguishes "loading" from "hung".
; The S10 prep contract runs FIRST, unconditionally - even the header-only read is
; exposed to 5.2's SYNC corruption if an IRQ-enabled paged-playback note is ringing when
; Load+Enter is pressed (save avoids this via SMPRDY, but load can't know the slot's
; contents in advance). With 1-15 halted and osc 0 free-running IRQ-off, no DOC IRQ can
; release SYNC during any session (6: IRQ-off oscillators never interrupt), and osc 0
; grants the DOC-RAM write cycles every copy needs. Everything osc 0 can scan is $00-free
; (the boot wave and captures are $00-scrubbed; slots store the buffer verbatim = already
; scrubbed), so it cannot self-halt under the copy (free-run halts on $00).
; End: mirror a completed capture - osc 0 back to idle, SMPPLAY (points all 16 oscs at
; the sample) BEFORE SMPRDY, and the capture metadata restored AFTER SMPPLAY.
; ============================================================
; ---- [reclaimed] old SMLOAD body + D2 diagnostics ($B19F-$B34F, 433 bytes) deleted:
; ---- superseded by SMLOAD2 (L1 unified load). 634 bytes total returned to the code budget.

; ============================================================================
; ===== midiout14 block (formerly injected at $B350 by build_midiout14.py) =====
; ============================================================================

; ============================================================================
; SEALED OS (seal1) — robust SAVE + fast motor-persist LOAD, MIDI diagnostics REMOVED.
; Derived from SL3 (hardware-validated). The disk logic is byte-for-byte identical to SL3:
;   * SAVE: one disk session, single spin-up, DKWSEC robust write (sentinel + 16-byte sled + bounded
;     retry + RESTORE), STATICALLY SKIPS the cursed sector idx32 (reltrack5 sec3) so the RESTORE/RNF
;     retry storm never runs.
;   * LOAD: 34 sessions but the motor LINE stays asserted across them (DKSETM portB=$20, ONE $F4C6 on
;     sector 0); each DOC copy runs in the motor-OFF state (stock DKREVIA) so the write lands; the
;     cursed sector idx32 is skipped and CONCEALED by copying the preceding 1 KB of good audio.
; Only the diagnostics are gone: no SysEx TX (MITX/MIDIPUT/markers), no MIDISET/MIDION/MIDIRST, no end
; report. The per-sector settle (STL, was MIDION's MIDISTL) and the post-read flush (FLU, was MIDIFL)
; are KEPT as plain timing loops with the SAME iteration counts — the reads rely on that timing.
; MIDI HARDWARE SEED for the future MIDI I/O feature (removed here, preserved in the project docs):
;   6850 ACIA:  $E100 = $03 (master reset) then $14 (/1, 8N1)
;   VIA T1 = $001E (T1 low=$1E, high=0) with ACR bit6 + PB7 -> a 31250-baud clock on PB7.
; Two operand-only redirects on stock D2 (all stock code incl. SMSAVE $B008 / SMLOAD $B19F identical):
;   $AF6C  JSR SMSAVE ($B008) -> SMSAVE2
;   $AF70  JSR SMLOAD ($B19F) -> SMLOAD2
; ============================================================================
; --- D2 routine addresses ---
OIRDRN  EQU   OIRDRAIN
DKSET   EQU   DKSETUP  ; DKSETUP
DKREV   EQU   DKREVIA  ; DKREVIA (also the motor-OFF teardown for each load copy)
SMPPLY  EQU   SMPPLAY  ; SMPPLAY
MOCHAN  EQU   $84FA            ; MIDI OUT channel (0-15). Loaded every pass from param 72 (1-16).
PBLAST  EQU   $84FB            ; last pitch-bend value transmitted (change detect)
; The stock pitch-wheel value ($9009) is written ONLY by the coroutine scan at $9039, which never runs
; during play, so it can't be used for live bend. WHEELRD (below) self-reads the ADC in the main loop.
PBRAW   EQU   $BE80            ; live pitch-wheel raw ADC (mux ch2, persistent), refreshed each pass
PBCEN   EQU   $BE81            ; self-calibrated pitch-wheel rest center (raw), captured at boot (MINIT)
WHCNT   EQU   $BE82            ; wheel/bend divider: sample + send only every WHDIV-th main-loop pass
WHDIV   EQU   1                ; S97: sample the wheel EVERY pass. S92 set 2, which was fine for the
;                                local engine but left MIDI far too sparse - see WHTXDIV.
;                                Original S92 note follows.
;                                S92: wheel SAMPLING divider. Was 8, which also throttled the LOCAL
;                                bend to one update per 8 passes - that is the "only 3-4 big steps"
;                                Viz hears while sweeping. The pitch resolution was never the
;                                problem: 33 distinct levels were measured in the unified50 sweep,
;                                many only 5 cents apart. It is the UPDATE RATE.
WHTXDIV EQU   1                ; S97: transmit on EVERY wheel read. Measured from Viz's MIDI-OX logs:
;                                stock sends bend every ~12ms with the MSB stepping by 1; unified55
;                                sent every ~105ms with the MSB jumping 3-11 at a time. Working back,
;                                one main-loop pass is about 26ms, so the old divider throttled bend
;                                to ~4 messages/second. Even at every pass this is 38 msgs/s = 114
;                                bytes/s, under 4% of MIDI's 3125 bytes/s - the flooding the original
;                                divider guarded against cannot happen at this loop rate. Messages
;                                still only leave on a CHANGE, so a still wheel costs nothing.
;                                S96 note follows.
;                                S96: halved, so bend goes out every 4 passes instead of 8 - the
;                                messages only leave on an actual change, so this raises the ceiling
;                                without adding traffic when the wheel is still.
;                                ...and the MIDI TRANSMIT divider on top of it, so bend messages
;                                still go out at the original 1-in-8 rate (2 x 4) and cannot
;                                saturate the serial port, while the engine tracks 4x more finely.
WHTXC   EQU   $865D            ; MIDI bend transmit countdown
MWLAST  EQU   $BE83            ; last mod-wheel value transmitted as CC1 (change detect)
MDAT2   EQU   $BE84            ; scratch: 2nd data byte for the shared MSEND 3-byte transmit helper
                               ; (only when param 71 mod-wheel-enable is on) -> CC1 needs param 71 on
NOTETAB EQU   $BE00            ; 128-byte per-key latch: transmitted MIDI note for each KBKEY. In free
                               ; RAM above the OS (unreferenced; stack top $BF80 never reaches here).
                               ; New vars live just above it at $BE80+ (also free, well below the stack).
MTUNE   EQU   $8440            ; engine coarse transpose (param 11 - 60), semitones (added to pitch)
MOCTV   EQU   $84CD            ; engine octave transpose (Sample Upper/Lower buttons), +/-12 per press
NOTEOFS EQU   36               ; KBKEY + 36 + MTUNE + MOCTV = MIDI note out. 36 = engine pitch base 14
                               ; ($9B47) + the freqtab->MIDI alignment (22); matches the sounding pitch.
; --- vars ---
PATCHBF EQU   $8C00
DKRTRY  EQU   $84F9
; metadata target vars (load)

; (block ORG removed: base code ends at exactly $B350, so this lands there)

; ================= disk-op timing (kept from the debug build; NO MIDI) =================
; STL: per-sector settle (was MIDION's MIDISTL, same $2000 count) between DKSETM and the read.
STL
        PSHS  X
        LDX   #$2000
STL1
        LEAX  -1,X
        BNE   STL1
        PULS  X,PC
; FLU: post-read flush/settle (was MIDIFL, same $0800 count) between the read and the teardown.
FLU
        PSHS  X
        LDX   #$0800
FLU1
        LEAX  -1,X
        BNE   FLU1
        PULS  X,PC

; ================= DKWSEC: robust seek+write (SAVE) =================
; Bounded retry (memory counter DKRTRY) + RESTORE on write-fail. Returns A = retry count (0 clean,
; $66 gave up). Sentinel ($8006) + 16-byte NOP sled per raw ROM call.
DKWSEC
        CLR   DKRTRY
DKWS1
        LDA   #$FF
        STA   $8006
        JSR   $F3F1            ; error-checked seek (ROM $F3F1 returns via RTS to caller+3 -> no sled)
        LDA   $8006
        BEQ   DKWSKO           ; seek ok -> write
        BRA   DKWRTY
DKWSKO
        LDA   #$FF
        STA   $8006
        JSR   $F476            ; write wrapper (ROM $F476 spins to completion then RTS to caller+3; it
        LDA   $8006            ; sets $8006 before returning -> the old 16-byte NOP sled was dead code)
        BEQ   DKWSOK           ; write ok -> done
        LDA   #$FF
        STA   $8006
        JSR   $F066            ; RESTORE: recalibrate head to track 0 (ROM $F066 returns to caller+3 -> no sled)
DKWRTY
        INC   DKRTRY
        LDA   DKRTRY
        CMPA  #$03
        BCC   DKWSGV
        JMP   DKWS1
DKWSGV
        LDA   #$66
        RTS
DKWSOK
        LDA   DKRTRY
        RTS

; ================= DKRSEC: robust seek+read (LOAD) =================
DKRSEC
        CLR   DKRTRY
DKRS1
        LDA   #$FF
        STA   $8006
        JSR   $F3F1            ; error-checked seek (ROM $F3F1 returns via RTS to caller+3 -> no sled)
        LDA   $8006
        BEQ   DKRSKO           ; seek ok
        BRA   DKRRTY
DKRSKO
        LDA   #$FF
        STA   $8006
        JSR   $F448            ; read wrapper (ROM $F448 spins to completion then RTS to caller+3; it
        LDA   $8006            ; sets $8006 before returning -> the old 16-byte NOP sled was dead code)
        BEQ   DKRSOK           ; read ok
DKRRTY
        INC   DKRTRY
        LDA   DKRTRY
        CMPA  #$03
        BCC   DKRGV
        JMP   DKRS1
DKRGV
        LDA   #$66
        RTS
DKRSOK
        LDA   DKRTRY
        RTS

; ================= DKSETM: motor-persist disk setup (LOAD sample loop only) =================
; = DKSETUP but portB=$20 (MOTOR ON, bit4=0) instead of $30, and NO VIA-reg re-save.
DKSETM
        LDA   #$20              ; port B: bank 0, MOTOR ON (bit4=0); DKSETUP passes $30 (motor off)
; DKCOM (S226R): the whole VIA/FDC/ACIA setup below was duplicated verbatim between DKSETUP and
; DKSETM except for the port B byte, which now arrives in A. DKSETM (no FIRQ mask, no VIA re-save)
; falls straight in; DKSETUP does its save prologue first and LBRAs here.
DKCOM
        PSHS  A                 ; park the port B value across the DP/FDC setup
        LDA   #$E8
        TFR   A,DP
        JSR   $F08F             ; WD1772 force-interrupt / reset
        LDA   #$7F
        STA   $E20E             ; IER: disable VIA interrupts (so only the FDC drives the transfer)
        LDA   #$CC
        STA   $E20B             ; ACR
        LDA   #$0E
        STA   $E20C             ; PCR
        LDA   #$1F
        STA   $E203             ; DDRA
        PULS  A
        STA   $E200             ; port B ($30 save path / $20 motor-persist load path)
        CLR   $E204
        CLR   $E205             ; stop T1 (TREST reloads it afterward)
        LDD   #$1388
        STB   $E208
        STA   $E209             ; T2
        LDA   #$03
        STA   $E100             ; ACIA (MIDI) master reset (left reset = MIDI-quiet)
        LDA   #$01
        STA   $BF8C             ; loader flag
        RTS

; ================= SMSAVE2: robust save (ONE disk session), diagnostics removed =================
SMSAVE2
        LDA   ROTPG             ; S226: the saved slot stores the UNROTATED buffer + LOGICAL
        BEQ   SM2NR             ; loop vars - no header change, and every extraction tool sees
        STA   LSTART            ; the layout the params describe. Live vars go logical FIRST
        ADDA  ENDPG             ; (ROTAPPLY never touches them): loop start = the rotation,
        STA   ENDPG             ; loop end = physical end + rotation. Loop saves store no
        CLRA                    ; marker (S126) - ROTAPPLY removes ours before the walk.
        JSR   ROTAPPLY          ; The first forced resync (<~1s) re-rotates after the save;
SM2NR                           ; until then notes route to the pager, which is merely ticky.
        JSR   HDRPACK
        TST   SMPRDY
        BEQ   SM2GO
        LDA   #$00
        JSR   PSEGL
        CLR   $EC40
        JSR   OSCHALT
        LDA   #$01
        JSR   PSEGL
        CLR   $ECA0
        LDA   #$02
        JSR   PSEGL
        JSR   OIRDRN
        LDA   #$03
        JSR   PSEGL
SM2GO
        JSR   DKSET            ; VIA disk mode + DP=$E8 + ACIA reset + ACR=$CC
        JSR   $F4C6            ; motor on + spin-up (ONE, whole save)
        JSR   STL              ; settle (was MIDION)
        TST   SMPRDY
        BEQ   SM2HDR
        LDX   #SMTAB
        STX   SMTPTR
        LDD   #$0000
        STD   SMDOC
        CLR   SMIDX
SM2LP
        LDX   SMTPTR
        LDA   ,X
        ADDA  SLTRK
        STA   $8002
        LDA   1,X
        STA   $8003
        LDD   SMDOC
        STD   $8004
; S213 RESOLVED (unified147): the "cursed sector" (idx32, reltrack5 sec3) was MISATTRIBUTED.
; The cursediag146 diagnostic wrote it CLEANLY on the FIRST attempt on two different slots
; (header-tail verdict $D6 $29 $00 twice; sector flux = real audio, byte-continuous with both
; neighbors). The static skip dated from the pre-sentinel/pre-status-read era - the S13/S14
; forensics show the missing-sector holes MOVED between runs (idx 32/31/16): the ~3%/call
; ROM-JSR bypass race, not a property of this sector. Under the modern DKWSEC the write is
; ordinary. All 34 sectors are now written; the load-side concealment is gone too.
        JSR   DKWSEC           ; robust seek+write (all 34 sectors, S213)
SM2ADV
        LDX   SMTPTR
        LDA   1,X
        LEAX  2,X
        STX   SMTPTR
        CMPA  #$05
        BEQ   SM2S5
        LDD   SMDOC
        ADDD  #$0400
        BRA   SM2AW
SM2S5   LDD   SMDOC
        ADDD  #$0200
SM2AW   STD   SMDOC
        INC   SMIDX
        LDA   SMIDX
        CMPA  #$22             ; 34 sectors
        BNE   SM2LP
SM2HDR
        LDA   SLTRK
        ADDA  #$04
        STA   $8002
        LDA   #$05
        STA   $8003
        LDD   #PATCHBF
        STD   $8004
        JSR   DKWSEC           ; header LAST
        JSR   FLU              ; flush/settle before the teardown changes the timers
        LDA   $E800
        JSR   $F4D6            ; motor off
        JSR   DKREV            ; teardown
        TST   SMPRDY
        BEQ   SM2DONE
        LDA   #$01
        STA   $ECA0            ; osc0 back to idle
        LDA   #$04
        JSR   PSEGL
SM2DONE
        RTS

; ================= SMLOAD2: fast motor-persist load, diagnostics removed =================
SMLOAD2
; S93: light the display through the load, the way SMSAVE2 already does with its PSEGL stages. Both
; operations block for a long time with the multiplexer stopped, so whatever segment happened to be
; lit when the call started is all you see - which is why save looks alive and load looked dead.
        LDA   #$00
        JSR   PSEGL
        CLR   $EC40
        JSR   OSCHALT
        CLR   $ECA0
        JSR   OIRDRN
        LDA   #$01
        JSR   PSEGL
; --- header session (stock C3 shape: motor spins up + down here) ---
; S160: POISON the magic BEFORE the read is set up. After a SAVE, PATCHBF still holds the header just
; written, valid $C3/$3C magic and all - so if the read does not land, the stale magic passes the
; check and the load proceeds as though a real slot had been read. $FF is neither valid magic nor an
; empty slot's zeros, so a read that does not happen now reports a bad read instead of impersonating
; whichever slot was touched last.
; S159 put these three instructions AFTER DKRSEC, which wiped the bytes the read had just delivered -
; hence "the saw never loads". The lesson is the one this project keeps relearning: an edit anchored
; by pattern match must be checked against the surrounding EXECUTION ORDER, not just the text.
; S161: RETRY the header read. The poison makes a read that did not land visible ($FF/$FF instead of
; a stale header impersonating a real slot) - and on hardware it turns out the first one or two reads
; after a POWER CYCLE genuinely do not land, so the honest report was "bad read" and the sample
; stayed. The ROM's own disk layer checks status after every call, which is why the boot loader never
; fails silently; ours did not check at all. Three attempts costs nothing when the first succeeds.
; S162: sixteen attempts, not three. DKRSEC already retries internally three times - but its loop
; redoes only the seek and read, NOT the destination pointer at $8004 or the track/sector at
; $8002/$8003. If the ROM read consumes or advances that pointer, only the FIRST of its three tries
; lands in PATCHBF at all, which makes THIS loop - which re-establishes the whole setup every pass -
; the only one that genuinely retries.
; Measured on hardware: up to four presses of Load were needed, i.e. about a dozen outer attempts,
; so three was simply too few. Sixteen costs nothing when the first succeeds and bounds the worst
; case at roughly a second and a half.
; S163: WAIT FOR THE DRIVE before the first read. Viz's pattern - sixteen rapid retries failing,
; then success on the very next press - is not random flakiness. Something stateful changes between
; presses, and the obvious candidate is MOTOR SPIN-UP: all sixteen attempts complete far faster than
; the drive can reach speed, so they fail as a group and the next press finds the motor already
; turning. A retry count cannot fix that; only waiting can.
; ~165ms at 2 MHz, once per load, before any seek or read is attempted.
; S164: the wait now happens AFTER the motor is switched on, which is what DKSET does. S163 put it
; BEFORE DKSET - so it waited with the drive still stopped, which achieved nothing except making the
; load slower, and the attempts got worse rather than better. Third placement error of this arc:
; PFIND after LDX, the poison after the read, and now this. The text matched each time; the
; EXECUTION ORDER did not.
; DKSET is also lifted OUT of the retry loop. It configures the VIA for disk mode and starts the
; motor - neither needs redoing per attempt - so the wait is paid once instead of sixteen times, and
; a retry now repeats only the part that can actually fail: the setup, the seek and the read.
        LDA   #$10
        STA   SMLRTY
        JSR   DKSET             ; VIA to disk mode, motor ON
; S166: the spin-up wait is REMOVED for this build. It is the theory the diagnostic exists to test,
; so measuring without it is cleaner - and it frees the bytes the report needs to be legal.
SMLRDTRY
        LDA   #$FF
        STA   PATCHBF
        STA   PATCHBF+1
        LDA   SLTRK
        ADDA  #$04
        STA   $8002
        LDA   #$05
        STA   $8003
        LDD   #PATCHBF
        STD   $8004
        JSR   $F4C6
        JSR   STL              ; settle (was MIDION)
        JSR   DKRSEC
; S165: DKRSEC tells us what happened and we have been discarding it. It returns $66 when the ROM's
; error-checked layer gave up after its own three tries, or the internal attempt number (0-2) when a
; read succeeded. Recording it alongside the poison separates two very different faults:
;   $66                          -> the reads genuinely FAIL at the ROM layer
;   0-2 with the poison intact   -> the read reported SUCCESS and the data landed elsewhere, which
;                                   would point straight at the destination pointer at $8004
        JSR   FLU
        LDA   $E800
        JSR   $F4D6
        JSR   DKREV
; --- validate magic ---
; S156: an EMPTY slot is not an error - it restores the DEFAULT WAVE. A slot that has never been
; written reads back as zeros (every re-flash blanks tracks 11-79), so all-zero magic means "empty"
; while anything else means the header is present but wrong, i.e. a genuine bad read. Separating the
; two gives the player a way back to the synth wave after sampling AND an honest distinction between
; "nothing was stored there" and "the load failed".
        LDA   PATCHBF
        CMPA  #$FF
        BNE   SMLRDOK
        LDA   PATCHBF+1
        CMPA  #$FF
        BNE   SMLRDOK
        DEC   SMLRTY            ; still poisoned -> the read never landed -> try again
        LBNE  SMLRDTRY
SMLRDOK
        LDA   PATCHBF
        ORA   PATCHBF+1
        LBEQ  SMLEMPTY          ; both magic bytes zero -> empty slot
        LDA   PATCHBF
        CMPA  #$C3
        LBNE  SMLBAD
        LDA   PATCHBF+1
        CMPA  #$3C
        LBNE  SMLBAD
; S214: VERSION GATE RESTORED. S108 removed it on the premise that a header can only be read by
; the build that wrote it - but the slot_d2 SUBSTRATE ships stale v2 headers in slots 1/4/5/9 on
; every flashed image, and a v2 header swallowed as v3 loads 45 pre-renumbering param values onto
; the wrong params (Viz's "weird metallic mess", which then persists through every later empty-slot
; load until reset-all). Version != 3 is now an honest bad-load.
        LDA   PATCHBF+2
        SUBA  #$03              ; S232: accept v3 (sample manager, 52), v4 (1.2, 53), v5 (54)
        CMPA  #$02
        LBHI  SMLBAD            ; anything else is still an honest bad-load (S214)
SMLVOK
        LDA   #$02
        JSR   PSEGL             ; S93: header read done, params next
; --- restore PARMTAB; the length depends on the header version (S88) ---
; S108: the cross-version length dispatch is REMOVED. Re-flashing the OS zeroes tracks 11-79, so
; every build wipes every slot - a header can only ever be read by the same build that wrote it, and
; the older layouts it handled cannot exist on a disk this code will ever see. The version byte is
; still written, so the dispatch can return if slots ever survive a flash.
; S230: v4 = all 53 entries; v3 (sample-manager slots) = 52 entries, and the appended
; LFO-range entry is re-initialized to its default so a stale live value can't leak in.
; S232: v5 = all 54 entries; v4 lacks 77; v3 lacks 76 and 77. Missing tail entries are
; re-initialized to defaults below (77 = receive ON).
        LDA   PATCHBF+2
        LDB   #(NPARM2-2)*4     ; v3: 208 bytes
        CMPA  #$04
        BCS   SMLPGO
        LDB   #(NPARM2-1)*4     ; v4: 212 bytes
        CMPA  #$04
        BEQ   SMLPGO
        LDB   #NPARM2*4         ; v5: 216 bytes
SMLPGO
        LDX   #PATCHBF+4
        LDY   #PARMTAB
SMLPP
        LDA   ,X+
        STA   ,Y+
        DECB
        BNE   SMLPP
        LDA   PATCHBF+2         ; X = metadata pointer: untouched below (extended stores)
        CMPA  #$05
        BEQ   SMLPD             ; v5: the full table came from the header
        CMPA  #$04
        BEQ   SMLP77            ; v4: only 77 is missing
        LDD   #$4C00            ; v3: {76,0,0,1}
        STD   PARMTAB+(NPARM2-2)*4
        LDD   #$0001
        STD   PARMTAB+(NPARM2-2)*4+2
SMLP77
        LDD   #$4D00            ; v3/v4: {77,0,0,1} = MIDI mod wheel receive ON
        STD   PARMTAB+(NPARM2-1)*4
        LDD   #$0001
        STD   PARMTAB+(NPARM2-1)*4+2
SMLPD
; --- stash metadata: X is already just past the param block, whichever length it was, so there is
;     no offset to keep in step with the version ---
        LDY   #HDRMETA
        LDB   #17
SMLMS
        LDA   ,X+
        STA   ,Y+
        DECB
        BNE   SMLMS
; S112: adopt the loaded buffer's orientation. A slot saved while reversed holds reversed audio, and
; its parameter says so - setting RVLAST from it stops SYNCP reversing an already-reversed buffer.
        PSHS  A,B,X,Y
        LDA   #SP_REV
        JSR   PFIND
        STA   RVLAST
        PULS  A,B,X,Y
; --- flags gate ---
        LDA   PATCHBF+3
        ANDA  #$01
        LBEQ  SMLNOS
; --- sample loop ---
        LDX   #SMTAB
        STX   SMTPTR
        LDD   #$0000
        STD   SMDOC
        CLR   SMIDX
SMLLP
        LDX   SMTPTR
        LDA   1,X
        CMPA  #$05
        BEQ   SMLS5
        LDD   #$0400
        BRA   SMLSW
SMLS5   LDD   #$0200
SMLSW   STD   SMCNT
; S213 RESOLVED (unified147): the idx32 skip + concealment are REMOVED - the save writes the
; sector now (see SMSAVE2), so all 34 sectors are read from disk like any other. Legacy slots
; (<=146 saves, idx32 all zeros) cannot reach a 147 disk on hardware (every re-flash blanks
; tracks 11-79); disk images carrying legacy slots are the sample manager's problem, and it
; bakes the old concealment in at import when it sees the all-zero idx32 fingerprint.
        JSR   DKSETM           ; motor-persist setup (portB=$20 motor ON, no SV re-save)
        LDX   SMTPTR
        LDA   ,X
        ADDA  SLTRK
        STA   $8002
        LDA   1,X
        STA   $8003
        LDD   #PATCHBF
        STD   $8004
        LDA   SMIDX
        BNE   SMLDNSU          ; sectors 1-33: drive already spinning, skip the spin-up
        JSR   $F4C6            ; FIRST sample sector only: real spin-up (motor then kept alive)
SMLDNSU
        JSR   STL              ; settle (was MIDION)
        JSR   DKRSEC
        JSR   FLU
        LDA   $E800            ; clear latent INTRQ (NO $F4D6: leave the drive spinning)
        JSR   DKREV            ; STOCK teardown -> normal state, MOTOR OFF: the copy lands
        LDD   SMDOC
        ADDD  SMCNT
        STD   SMDEND
        LDX   #PATCHBF
        LDY   SMDOC
SMLCP
        LDA   ,X+
        BNE   SMLCPN
        LDA   #$01
SMLCPN
        STA   ,Y+
        CMPY  SMDEND
        BNE   SMLCP
        LDD   SMDEND
        STD   SMDOC
SMLADV
        LDX   SMTPTR
        LEAX  2,X
        STX   SMTPTR
        INC   SMIDX
        LDA   SMIDX
        CMPA  #$22
        LBNE  SMLLP
; (drive stops naturally: the last sector's DKREVIA left the motor OFF)
; S214: RE-PLACE THE ONE-SHOT END MARKER that the load's $00->$01 scrub erased. Without it a
; loaded one-shot never halts: it plays through two 8x$01 dips (clicks) and free-run WRAPS back
; into the attack until release - the "glitch at the end" (pre-existing in every prior build,
; unmasked once the concealment click died). MUST run BEFORE osc 0 is idled: DOC writes need a
; running oscillator (S157), and because the marker bytes ARE zeros, osc 0 can self-halt by
; scanning one mid-write - so every byte is written with osc 0 re-run first and verified by
; read-back (CPU DOC reads are always safe). Position: SENDPOS (HDRMETA+3) if set; otherwise the
; capture crossing marker's 8-zero run is recovered from PATCHBF, which still holds the RAW
; (pre-scrub) final KB - the last sector loaded is idx33 = DOC $7C00-$7FFF, and the capture
; always places its marker inside that KB ($7FD9..$7FF8).
        LDA   HDRMETA+5         ; LMODE: loop mode wants NO marker at all (S126) - the pager
        BNE   SMLMKDN           ; hands over early on a mid-page $00. One-shot only.
        LDA   HDRMETA+3         ; SENDPOS image: high byte of marker offset, 0 = none
        BEQ   SMLMKSC
        CLRB
        TFR   D,X               ; X = SENDPOS<<8 (DOC address)
        BRA   SMLMKGO
SMLMKSC
        LDX   #PATCHBF
        CLRB                    ; consecutive-zero counter
SMLMKS1
        LDA   ,X+
        BEQ   SMLMKS3
        CLRB
        BRA   SMLMKS4
SMLMKS3
        INCB
        CMPB  #$08
        BEQ   SMLMKS5           ; found: X = one past the 8th zero
SMLMKS4
        CMPX  #PATCHBF+1024
        BNE   SMLMKS1
        BRA   SMLMKDN           ; no marker in the final KB (loop-mode save) -> nothing to place
SMLMKS5
        LEAX  -8,X              ; X -> first zero, still PATCHBF-relative
        TFR   X,D
        SUBD  #$1000            ; PATCHBF ($8C00) - $7C00 = $1000: translate to the DOC address
        TFR   D,X
SMLMKGO
        LDB   #$08
SMLMKW
        CLR   $ECA0             ; osc 0 RUNNING (it may have self-halted on a zero we just wrote)
        CLR   ,X
        LDA   ,X                ; read-back: did the write land?
        BNE   SMLMKW            ; no -> osc was halted at write time -> re-run and retry
        LEAX  1,X
        DECB
        BNE   SMLMKW
SMLMKDN
        LDA   #$01
        STA   $ECA0
; --- S53: derive playback res + shift from the stored RATE BEFORE SMPPLY (which writes $ECC0 from
;     SMPRES). The stored shift is ignored: pre-S53 fast-rate saves were captured broken and carried
;     invalid shifts. ---
        LDA   HDRMETA+1         ; stored capture prescaler N
        LDB   #$00              ; rate index 0 (N=8)
        CMPA  #$08
        BEQ   SMLDR1
        INCB                    ; rate index 1 (N=4)
        CMPA  #$04
        BEQ   SMLDR1
        INCB                    ; rate index 2 (N=2, S66)
        CMPA  #$02
        BEQ   SMLDR1
        INCB                    ; S233b: rate index 3 (N=1, rate 4) - anything else clamps here
SMLDR1
        LDX   #SMPRESTB         ; S55: index the SAME table capture uses (S54's octave res-bump had
        LDA   B,X               ; updated SMPRESTB but not this path's hardcoded $09/$08 copies ->
        STA   SMPRES            ; loaded samples played one octave up. Never duplicate the mapping.
        LDX   #TRIMBTB          ; S96: same idea for the tune base - one table, both paths
        LDA   B,X
        STA   TRIMBAS
        LDB   #$03
        STB   SMPSHFT           ; words are always shift-3
        JSR   SMPPLY
        LDA   HDRMETA+1
        STA   SMPPRE
        LDA   HDRMETA+2
        STA   SSTART
        LDA   HDRMETA+3
        STA   SENDPOS
        LDA   HDRMETA+4
        STA   SENDSAV
        LDA   HDRMETA+5
        STA   LMODE
        LDA   HDRMETA+6
        STA   LSTART
        LDA   HDRMETA+7
        STA   SENDPG
        LDA   HDRMETA+8
        STA   ENDPG
        LDX   #HDRMETA
        LEAX  9,X
        LDY   #SENDSV8
        LDB   #8
SMLM8
        LDA   ,X+
        STA   ,Y+
        DECB
        BNE   SMLM8
        LDA   #$01
        STA   SMPRDY           ; sample present
        CLR   LPSCRB           ; S222b: loaded sample -> its stored marker needs scrubbing
        CLR   ROTPG            ; S226: loaded audio is stored unrotated; the first sync pass
        RTS                    ; re-rotates it if the loaded params ask for a loop start
SMLNOS
        LDA   #$01
        STA   $ECA0
        RTS
SMLEMPTY
; Empty slot: rebuild the default wave and forget the sample.
; S157: RUN AN OSCILLATOR FIRST. CPU writes into DOC RAM only land while at least one oscillator is
; running to provide RAM-access cycles. At boot the generator works because it executes BEFORE OINIT
; halts everything and the ROM has left one going - but here every oscillator is stopped after the
; disk operation, so GENWAVE's 32768 writes went nowhere and the buffer kept whatever noise was in
; it. That is the silence-plus-hiss Viz heard. The sample load path is unaffected because the ROM
; performs that transfer itself.
; Volume is zeroed first so the running oscillator cannot be heard while the wave is being built.
        CLR   $EC40             ; oscillator 0 volume = 0
        CLR   $ECA0             ; control = 0 -> running, so DOC RAM accepts CPU writes
        JSR   GENWAVE
; S158: RE-ESTABLISH the oscillator registers, as a successful load does via SMPPLY. Skipping that
; was the click: the oscillators were left with whatever the disk operation had put in their wtptr
; and size/resolution words, so the first note-on drove them from a stale configuration. Setting
; SMPRES to $38 first - T=7, the 32768-sample table the boot wave uses - makes SMPPLY write exactly
; the boot configuration rather than a sample one, which is what the regenerated wave needs.
        LDA   #$38
        STA   SMPRES
        JSR   SMPPLY
        CLR   SMPRDY            ; no sample loaded -> the engine plays the synth wave again
        CLR   SSTART
        CLR   SENDPOS           ; the regenerated buffer carries no end marker
        CLR   ROTPG             ; S226: fresh saw = unrotated (a stale rotation would send
                                ; the next loop-off walking a buffer that never moved)
; S226c: AN EMPTY SLOT IS A FACTORY PATCH. Params now reset to defaults here, exactly as
; LPSCAN's reset-all does - PBUILD rewrites the base set and leaves the MINIT-appended
; control/MIDI group (71-75) alone, so MIDI channel/octave survive. Long-standing gap, not
; a 162 regression (the 161 source has no reset on this path and the 161<->162 instruction
; diff is exhaustive): the empty slot loaded the saw but kept whatever params were live.
; SYNCP picks the new values up on its next pass via the checksum.
        JSR   PBUILD
; S158: the PSEGL "codes" are REMOVED. PSEGL lights one segment column during a disk operation,
; because the main loop is stopped then - the instant the load returns the multiplexer redraws and
; the signal is gone. It was a flicker, not an indicator, and pretending otherwise is worse than
; having nothing. A real one needs a latched flag plus display logic; it is on the punch list.
; The audible signal is honest in the meantime: an empty slot brings the default sawtooth back.
        BRA   SMLNOS            ; S226c: identical tail (osc 0 back on + RTS) - deduped to pay
                                ; for the PBUILD call above
SMLBAD
        LDA   #$01
        STA   $ECA0
        RTS

; ================= ENVWRAP: T2-based envelope tick (frees T1 for the MIDI clock) =================
; The main loop's "JSR TICKALL" ($99B0) is redirected here, and its gate now tests the T2 flag
; (BITA #$20). Boot + DKREVIA are patched to load/restore the ~333Hz tick value into T2 ($1770)
; instead of T1, so T1 is free to become the continuous 31250 MIDI clock. Reload+restart T2 (which
; also clears its IFR flag) FIRST so the tick's own runtime isn't counted in the period, then
; tail-call TICKALL (its RTS returns to the main loop).
ENVWRAP
        LDA   #$70
        STA   $E208            ; T2 counter low = $70
        LDA   #$17
        STA   $E209            ; T2 counter high = $17 -> reload+start T2=$1770, clears its flag
; --- round-robin filter CV refresh (droop fix). The CEM3328 cutoff/resonance CVs are sample-and-
;     holds that droop over ~1s if never restrobed, and FREF is write-on-change (pfix5: strobing
;     every pass injects switching noise). Every 8 ticks (24ms) invalidate ONE voice's LFCUT/LFRES
;     cache to the $FF sentinel so FREF rewrites that voice's true values on its next pass. Full
;     cycle = 8 voices x 8 ticks = 192ms per filter: ~5x faster than the droop, ~600x slower than
;     the per-pass strobing that buzzed. RRDIV/RRVOICE self-start from any boot garbage (worst
;     case: first refresh delayed up to 255 ticks, then regular). ---
; S219: the ENTIRE round-robin cache-invalidation machinery DELETED (RRDIV/RRVOICE/RRRESC era,
; S79-S91). It existed to make the old write-on-change FREF re-strobe drooping CV S&Hs; the
; stock-exact refresh (S207-208) rewrites every channel every pass unconditionally, so both the
; droop problem and the caches it poked are gone. Audited against the S207-S210 log per the punch
; list before deletion.
; S225b: THIS JMP IS ENVWRAP'S TAIL CALL, REACHED BY FALL-THROUGH. It has no label
; references, and the S225 reclaim deleted it as "unreferenced" - which broke the OS
; outright (every ~3ms envelope tick fell through into MINIT: T1/ACIA re-init at 333Hz
; = no envelopes, no sound, MIDI chaos). Unreferenced is NOT unreachable. DO NOT DELETE.
ENVWT
        JMP   TICKALL

; ================= MIDI OUT =================
; MINIT: boot MIDI bring-up (redirected from the pre-MAIN "JSR SYNCP" at $98A1). Runs SYNCP, then sets
; T1=$001E free-run (PB7 = the 31250 bit clock the ACIA transmits on) + the 6850 ACIA for TX (/1, 8N1,
; interrupts OFF), and inits the MIDI-out channel. The envelope tick runs on T2 (seal2), so T1 is free
; to be the continuous bit clock. RX is not used - transmit only.
MINIT
        JSR   SYNCP
; S139: MAKE PB7 AN ACTUAL OUTPUT FIRST. The ROM sets DDRB = $1F at $F0F4 - PB0-PB4 outputs, and
; PB5, PB6, PB7 INPUTS - and NEITHER the stock OS NOR our OS ever writes DDRB again. So every build
; so far has asked T1 to drive PB7 while the direction register still called it an input. ACR bit 7
; is documented to override DDRB, but an override against a disagreeing direction register gives a
; marginal drive, and a marginal drive is FREQUENCY DEPENDENT. That accounts for every result:
;     latch $1E ->  31 kHz  slow enough for a weak drive to swing the net -> transmit CORRECT
;     latch $01 -> 333 kHz  marginal                                      -> GARBLED
;     latch $00 -> 500 kHz  never resolves                                -> NO OUTPUT
; and the pin sampler still saw movement at latch 0 (127, clamped) because the VIA's internal node
; toggles even when the pin cannot settle.
        LDA   $E202
        ORA   #$80             ; DDRB bit 7 = 1: PB7 is a genuine output
        STA   $E202
        LDA   $E20B
        ORA   #$C0             ; ACR: T1 free-run (b6) + PB7 square-wave out (b7) = the bit clock
        STA   $E20B
; S128: T1 latch 0, giving PB7 = 500 kHz - sixteen times the bit rate, which is what asynchronous
; RECEIVE needs. Our old $001E gave PB7 = 31250 and the ACIA ran /1: fine for transmit, because we
; generate both the clock and the data, but /1 cannot sample an incoming stream whose phase we do not
; know. That is why nothing arrived. The stock OS does exactly this - it clears both latch bytes and
; writes $95 - which is how it receives on the same hardware.
; Transmit is unaffected: 500 kHz / 16 is the same 31250 baud as 31250 / 1.
; T1 is ONLY the MIDI bit clock here; the envelope tick runs on T2 ($E208/$E209 = $1770), so this
; changes nothing else.
; S129: REVERTED to the timing that is known to transmit correctly. S128 set the latch to 0 for a
; 500 kHz PB7 and /16, copying stock - but on this machine that produced a GARBLED transmit stream
; (MIDI-OX decoding endless $FE/$FF, which is what framing errors look like), so PB7 at latch 0 is
; not landing where the arithmetic says. Rather than iterate blind, transmit goes back to what is
; proven and receive is switched off until the clock is understood.
; S133: back to the only configuration proven to work on this machine.
;   T1 counter $001E -> PB7 = 31250, ACIA /1 -> 31250 baud, transmit only.
; MIDI IN is parked. Four clock configurations were tried and the results are consistent and
; conclusive about what does NOT work - see the S133 log - but a fifth guess is not the right way
; to spend hardware cycles. The schematic is the next step, not another build.
        CLR   $E206
        CLR   $E207
        CLR   $E204
        CLR   $E205            ; S139: T1 = 0 -> PB7 = 500 kHz, exactly what stock writes and exactly
;                                what the schematic labels on the ACIA clock net. /16 gives 31250.
        LDA   #$03
        STA   $E100            ; 6850 master reset
; S127: install our FIRQ handler and enable RECEIVE interrupts. The ROM's FIRQ vector points at
; $800B in RAM, which holds a JMP - stock's, because $8000-$95FF comes from the base disk and we do
; not build that region. Overwrite it BEFORE enabling the interrupt, or the first byte received
; would vector into stock's handler.
        LDA   #$A5
        STA   FRJIT             ; S189: LFSR seed (must be non-zero)
        CLR   MIRHD
        CLR   MIRTL
        CLR   MISTAT
        CLR   MICNT
        LDA   #$7E              ; JMP extended
        STA   $800B
        LDX   #MIDIRQ
        STX   $800C
; S134: /16, the divider stock uses and the only one that can receive an asynchronous stream.
; Receive interrupts stay OFF in this build so it tests the CLOCK alone - if the clock is right,
; enabling receive afterwards is a single constant.
        LDA   #$95
        STA   $E100            ; S139: /16 + RECEIVE ENABLED - stock's control word
; S145: UNMASK FIRQ so received bytes can actually be taken. The 6809 leaves reset with I and F both
; SET, and until now the only ANDCC in this OS was the one at DKREVIA - so F was never cleared at
; boot and the handler could never run.
        ANDCC #$BF             ; clear F
        LDX   #NOTETAB         ; clear the per-key note latch
;              ^^^^^^^ S145: RESTORED. My S140 edit replaced the line "STA $E100 / LDX #NOTETAB"
; with "STA $E100 / ANDCC #$BF" and silently DROPPED the LDX. MINITCL below then ran with X still
; holding MIDIRQ, so the boot cleared 128 bytes starting AT THE FIRQ HANDLER - wiping the handler,
; the parser and whatever followed. THAT is what hung unified101, 102, 103 and 104. It was never the
; F flag, never a FIRQ storm, and never a second interrupt source: it was a deleted instruction.
        LDB   #128
MINITCL CLR   ,X+
        DECB
        BNE   MINITCL
        LDX   #$87BC           ; S210: PARMTAB ($8700) + 47*4. COUPLED to the builder length -
;                                if PBUILD gains or loses an entry this MUST move with it (the
;                                post-build table audit catches a mismatch before anything ships).
; Control/MIDI group lives OUTSIDE PBUILD so LPSCAN reset-all does not touch it (S108 intent,
; kept through S210): 71 channel, 72 wheel function, 73 damping, 74 bend range, 75 wheel disable.
        LDD   #$4701            ; 71 - MIDI channel (1-16) (default 1)
        STD   ,X++
        LDD   #$0110            ; min 1, max 16
        STD   ,X++
        LDD   #$4800            ; 72 - mod wheel function (0=edit 1-4=LFO) (default 0)
        STD   ,X++
        LDD   #$0004            ; min 0, max 4
        STD   ,X++
        LDD   #$4901            ; 73 - mod wheel damping (default 1)
        STD   ,X++
        LDD   #$0003            ; min 0, max 3
        STD   ,X++
        LDD   #$4A02            ; 74 - pitch bend range (semitones) (default 2)
        STD   ,X++
        LDD   #$010C            ; min 1, max 12
        STD   ,X++
        LDD   #$4B00            ; 75 - pitch wheel disable (0=en 1=dis) [NEW S210] (default 0)
        STD   ,X++
        LDD   #$0001            ; min 0, max 1
        STD   ,X++
        LDD   #$4C00            ; 76 - LFO RANGE (0=low 1=high) [NEW S230] (default 0=low).
        STD   ,X++              ; Appended AFTER the control group: v3 headers (sample manager)
        LDD   #$0001            ; keep their exact 208-byte layout and the loader defaults this
        STD   ,X++              ; entry. Like 71-75 it survives LPSCAN reset-all. min 0, max 1
        LDD   #$4D00            ; 77 - MIDI MOD WHEEL RECEIVE (0=on 1=off) [NEW S232] (default 0=on).
        STD   ,X++              ; A CONTROL param like 71-75: survives reset-all (PBUILD never
        LDD   #$0001            ; writes it). 1 = received CC1 is ignored, so an external keyboard
        STD   ,X++              ; can be played while the Mirage's own wheel edits. min 0, max 1
; S103: the sample-tune entry now lives in the defaults builder, in numerical order after spec 05.
; MINIT appends only the MIDI channel (spec 72), which is numerically last anyway.
        ; (param 99 dummy park slot DEFERRED - out of block space; trivial to re-add once space is freed)
; --- boot-calibrate the pitch centre (spring-centred wheel is at centre at power-up; no notes yet) ---
        JSR   WHEELRD          ; proper ch2 read -> PBRAW
        LDA   PBRAW
        STA   PBCEN            ; pitch centre = rest raw (bend transmits deviation from here)
        LDA   #$40
        STA   PBLAST           ; last-bend baseline = MIDI centre ($2000) -> no spurious bend at boot
        LDA   #$01
        STA   WHCNT            ; run the wheel read on the first pass, then every WHDIV-th
                               ; (MWLAST left uninitialised -> at most one harmless CC1 sync on first move)
        RTS

; TREST: restore timers after a disk op (redirected from DKREVIA's old T1 restore). T1=$1E (MIDI
; clock) + T2=$1770 (envelope). Called by every DKREVIA (save teardown + each load-sector teardown).
TREST
        CLR   $E206
        CLR   $E207
        CLR   $E204
        CLR   $E205            ; S139: T1 = 0 -> PB7 = 500 kHz, exactly what stock writes and exactly
;                                what the schematic labels on the ACIA clock net. /16 gives 31250.
        LDA   #$70
        STA   $E208
        LDA   #$17
        STA   $E209            ; T2 = $1770 (envelope tick)
        RTS

; KBMIDI: main-loop hook (redirected from ack#1 "JSR KBSERV" at $98A7). Re-arm the ACIA TX config every
; pass so transmission survives a disk session (DKSETUP master-resets the ACIA). Writing $14 is a 6850
; no-op during normal play and never disturbs a byte mid-shift; after a save/load it restores TX. Then
; run the local keyboard service - the MONON/MONOFF hooks inside it emit the MIDI as keys are played.
KBMIDI
        LDA   #$95
        STA   $E100            ; S139: /16 + RECEIVE ENABLED - stock's control word
        LDA   #71              ; S210: MIDI channel is now spec 71 (was 72)
        JSR   PFIND            ; MIDI channel param (1-16)
        DECA
; S208 (bug: "loading a slot sometimes breaks MIDI"): PFIND returns 0 when the spec is ABSENT, and a
; slot restored with a damaged param block can lose or garble the spec-72 entry. 0-1 = $FF, and MSEND
; ORs the status with MOCHAN: $90|$FF = $FF = SYSTEM RESET - every note/bend transmits as System
; Reset (exactly what MIDI-OX logged) and the RX channel filter matches nothing, so BOTH directions
; die until a clean slot load restores the entry. Clamp at the point of use: anything outside 0-15
; falls back to channel 1. (A slot that breaks MIDI repeatably has a damaged saved param block -
; re-saving it heals the slot itself.)
        CMPA  #$10
        BCS   MOCOK            ; 0-15 -> valid
        CLRA                   ; absent/corrupt -> channel 1
MOCOK
        STA   MOCHAN           ; -> 0-15
        JSR   KBSERV           ; MONON/MONOFF fire here for note events
        DEC   WHCNT            ; only sample the wheel + send bend every WHDIV-th pass. Notes still
        BNE   KBMDONE          ; transmit on EVERY event (in KBSERV above) - only the wheel is throttled,
        LDA   #WHDIV           ; so fast playing keeps up while a wheel sweep can't flood the serial port.
        STA   WHCNT
        LDA   SMPSTAT
        CMPA  #$01
        BEQ   PBSKIP            ; S122: armed -> leave port B alone, the meter owns the mux
; S210: param 75 = pitch wheel disable. A drifting/faulty wheel can be taken out of the loop
; entirely: skip the ADC read and pin PBRAW at the boot-calibrated rest, so PBCALC's dead-band
; takes the at-rest path every pass. MIDI bend receive still works (the MBACT path owns the bend
; when the wheel is at rest), and PBTX sends one final return-to-centre, then goes silent.
        LDA   #SP_PWDIS
        JSR   PFIND
        TSTA
        BNE   PWOFF
        JSR   WHEELRD          ; refresh PBRAW from the pitch wheel (ch2) - LOCAL bend needs this often
        BRA   PWCALC
PWOFF
        LDA   PBCEN
        STA   PBRAW
PWCALC
        JSR   PBCALC           ; S98: derive PBDEV/PBACT from the reading just taken
PBSKIP
        DEC   WHTXC            ; S92: MIDI transmission stays on the original slower cadence
        BNE   KBMDONE
        LDA   #WHTXDIV
        STA   WHTXC
        JSR   PBTX             ; transmit pitch bend if the wheel moved
; --- MODTX inlined: mod wheel -> CC1 on change (from MWSERV's $841E; needs param 71 on) ---
        LDA   MWVAL
        LSRA                   ; 0-127
        CMPA  MWLAST
        BEQ   KBMDONE
        STA   MWLAST
        STA   MDAT2            ; data2 = value
        LDB   #$01             ; data1 = controller 1
        LDA   #$B0             ; control-change status $Bn
        JSR   MSEND
KBMDONE
        RTS

; WHEELRD: refresh the live pitch-wheel value with ONE atomic read of the DOC A/D ($ECE2). The stock scan
; ($9039) that feeds $9009 lives in the display coroutine and never runs while playing, so we read the ADC
; ourselves. This build keeps the analog mux PERSISTENTLY on ch2 (the pitch wheel) - selected once in
; MINIT, and MWSERV always restores whatever it found, so nothing steals it. Because ch2 has been selected
; since the previous pass (>> the 31us conversion time), each read returns a fully-settled ch2 value AND
; launches the next conversion in the background. So there is NO busy-wait here: a single indivisible LDB
; that cannot be split by an oscillator IRQ. (The old version's crash came from unmasking during a ~us-long
; settle loop between two reads, letting the oscillator IRQ land inside the A/D read while a note sounded.)
; Preserve CC + mask THROUGHOUT (the MWSERV discipline that fixed the crash). The A/D returns the value of
; the LAST completed conversion and starts a new one, so after switching the mux ch3->ch2 the FIRST read
; still holds MWSERV's ch3 (mod) value and the first ch2 conversion samples an analog mux that hasn't fully
; settled. Reading ch2 with a single 2-read let that stale/bled mod value through when the mod wheel was
; high. So: THREE reads - read1 launches a throwaway ch2 conversion; after settle1 (mux settles + that
; conversion completes) read2 is discarded but launches a FRESH conversion on the now-settled ch2 input;
; after settle2 read3 is that clean, fully-settled ch2 value. Then park ch3 for MWSERV.
WHEELRD
        PSHS  CC
        ORCC  #$10              ; S231b: mask IRQ ONLY (was #$50 = IRQ+FIRQ) - see below
; S231b: FIRQ STAYS OPEN. Only I is masked (IRQ is masked for good anyway - nothing in Orovela
;   clears I). Build 176's counters caught ACIA OVERRUNS (3/22/40 per hang, 0 framing errors):
;   this read masked FIRQ across all three settle loops, long enough for two back-to-back
;   MIDI bytes to land. MIDIRQ touches only $E100/$E101 and the ring - never port B or the
;   ADC - so a byte taken mid-settle only lengthens the settle. Stock ($9039) masks only
;   around the mux switch and runs its settle delay with interrupts ENABLED.
        LDA   $E200
        ANDA  #$FB
        ORA   #$08              ; mux -> ch2 (pitch)
        STA   $E200
        LDB   $ECE2             ; read1: flush stale value, launch a ch2 conversion (mux may not be settled)
        LDX   #$0010
WHS1    LEAX  -1,X
        BNE   WHS1              ; settle1: analog mux settles onto ch2 AND read1's conversion completes
        LDB   $ECE2             ; read2 (discard): launch a FRESH conversion on the now-settled ch2 input
        LDX   #$0010
WHS2    LEAX  -1,X
        BNE   WHS2              ; settle2: the fresh conversion completes (>> the ~30us convert time)
        LDB   $ECE2             ; read3: clean, fully-settled ch2 value
        STB   PBRAW
        LDA   $E200
        ORA   #$0C              ; mux -> ch3 (mod): launch a ch3 conversion so MWSERV reads ch3, not our ch2
        STA   $E200
; S208 (bug: "pitch bends edit the selected param"): the discard-read below LAUNCHES the conversion
; MWSERV will consume - and it used to fire IMMEDIATELY after the mux switch, so that conversion
; sampled ch3 through a mux still slewing away from ch2: the mod-wheel sample was BLED toward the
; pitch-wheel value. During a HELD bend the bleed is steady, so consecutive MWSERV samples AGREE and
; sail through the 24-count outlier filter - the editor then follows the pitch wheel (full-down from
; 35 landed on 49 = the pitch wheel's mapped CENTER, the giveaway). This is the exact mirror of the
; ch3->ch2 bleed documented above, which got a discard+settle; the return trip got neither. Same
; cure: settle before launching.
        LDX   #$0010
WHS3    LEAX  -1,X
        BNE   WHS3              ; settle3: the analog mux settles onto ch3 BEFORE the launch samples it
        LDB   $ECE2             ; discard (a clean ch3 conversion is now pending for MWSERV)
        PULS  CC
        RTS

; PBTX: transmit MIDI pitch-bend from the self-read pitch wheel (PBRAW), centred on the boot-calibrated
; rest position PBCEN. A +/-8 count DEAD-BAND around the centre is the key noise gate: at rest the wheel
; sits deep in the dead-band so the output is a ROCK-STABLE $40 and nothing is transmitted (this is what
; was flooding before). Outside it, value = clamp((raw-centre)+$40, 0..127), 1:1 like the stock local
; bend. 14-bit bend = value<<7 (LSB 0, MSB = value; centre $40 -> $2000). Only sends on a real change.
; Direction from the SUBTRACT BORROW, magnitude UNSIGNED, so the wheel's full physical throw (which
; exceeds 128 counts below centre) can't overflow an 8-bit signed dev and wrap the output to max (the
; old bug). Shrink dead-band (subtract 8 from the magnitude) so the response eases in smoothly from
; centre instead of jumping (the "weird quantization"). Up: $40 + (mag-8) clamped to $7F. Down:
; $40 - (mag-8) clamped to $00. Within +/-8 counts of centre -> exactly $40 (noise gate, no flood).
PBTX
; S96: transmit a FULL 14-bit bend, over the FULL wheel travel. The previous version clamped the
; magnitude to 63 - so the wheel saturated at just over half its travel and the rest of the sweep did
; nothing - and sent only a 7-bit value with the LSB hardwired to zero, i.e. 3.1-cent steps at a
; receiver set to +/-2 semitones. Now it reuses PBDEV, the same dead-banded signed deviation the
; local engine bends with, so MIDI and the internal voice always agree, and maps it as
; 8192 + dev*64: one ADC count becomes 64 LSB, about 1.5 cents, which is the wheel's own resolution.
; S173: require a REAL movement before transmitting. The S169 hysteresis only guards the rest/bend
; boundary - once the wheel sits off centre by more than 12 counts it STAYS in the bending state, and
; a single count of ADC jitter then changed PBDEV and put a message on the wire. That is why the
; stream continued with the wheel untouched, and why cranking the wheel and releasing sometimes
; stopped it: the wheel settled at a different resting count, sometimes inside the dead band and
; sometimes not. One or two counts is 1-3 cents at the default range - not worth a MIDI message.
        LDA   PBDEV
        SUBA  PBLAST
        BPL   PBTXP
        NEGA
PBTXP
        CMPA  #$03
        BLO   PBRET             ; moved less than three counts -> stay off the wire
        LDA   PBDEV
        STA   PBLAST
        LDB   PBDEV
        SEX                     ; D = sign-extended deviation
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA                    ; D = deviation * 64
        ADDD  #$2000            ; centre = 8192
        PSHS  B                 ; keep the low byte for the LSB
        ASLB
        ROLA                    ; A = value >> 7 = the 7-bit MSB
        STA   MDAT2             ; data2 = MSB
        PULS  B
        ANDB  #$7F              ; data1 = LSB
        LDA   #$E0              ; pitch-bend status $En
        JSR   MSEND
PBRET
        RTS

; MTX: transmit A as one MIDI byte. Polls TDRE (6850 status b1) until ready, then writes the byte.
; Preserves B (MSEND relies on that). NOTE: the bounded-timeout guard from earlier builds was removed to
; reclaim space for CC1/param 99 - safe because the TX bit clock (VIA T1) free-runs continuously so TDRE
; always sets within one byte-time; there is no operational path where this spins forever. Re-add the
; timeout once we free real code space (see the space-analysis handoff).
; S136: BOUNDED WAIT. The timeout guard was removed long ago on the reasoning that "the TX bit clock
; free-runs continuously so TDRE always sets; there is no operational path where this spins forever."
; unified95 disabled PB7 and found that path: with no bit clock TDRE never sets, MTX span forever and
; the machine did not boot - the display froze mid-multiplex. A dead clock should degrade to silent
; MIDI, never to a hang.
MTX
        PSHS  B,X
        LDX   #$1000           ; ~4ms at 2 MHz; one byte at 31250 baud takes 320us
MTX1    LDB   $E100
        BITB  #$02             ; TDRE (transmit data register empty)?
        BNE   MTXGO
        LEAX  -1,X
        BNE   MTX1
        PULS  B,X,PC           ; timed out - drop the byte rather than hang
MTXGO
        STA   $E101            ; write byte to the ACIA transmit register
        PULS  B,X,PC

; MSEND: transmit a 3-byte channel-voice message. A = status high bits ($90/$80/$E0/$B0) - OR'd with
; MOCHAN here; B = data1; MDAT2 = data2. (MTX preserves B, so data1 survives the status byte's send.)
; Tail-calls MTX for the last byte. Shared by MONON/MONOFF/PBTX/MODTX to avoid 4 copies of the send.
MSEND
        ORA   MOCHAN           ; full status byte (channel merged in)
        JSR   MTX
        TFR   B,A
        JSR   MTX              ; data1
        LDA   MDAT2
        JMP   MTX              ; data2 (tail-call -> MTX's RTS returns to MSEND's caller)

; MONON: hook at $A1C0 (was "JSR NOTEON" inside KBSERV). Do the real local note-on, then transmit a MIDI
; note-on for the played key. KBSERV has set KBKEY=$8421 and KBVEL=$8422. Status = $9n (n = MOCHAN).
; The MIDI note mirrors the engine's pitch index at $9B44 (KBKEY + $0E + MTUNE + MOCTV) plus the +22
; freqtab->MIDI alignment = KBKEY + NOTEOFS(36) + MTUNE + MOCTV, masked to 7 bits, so MIDI OUT follows
; the octave buttons and coarse transpose exactly like the sounding pitch (8-bit adds wrap like the engine).
MONON
        JSR   NOTEON           ; local voice first - unchanged synth behavior
        LDA   KBKEY            ; A = MIDI note for the key (current transpose)
        ADDA  #NOTEOFS
        ADDA  MTUNE
        ADDA  MOCTV
        ANDA  #$7F
        LDX   #NOTETAB         ; latch it so the matching note-off sends the SAME number
        LDB   KBKEY
        ANDB  #$7F
        STA   B,X              ; NOTETAB[KBKEY] = note
        TFR   A,B              ; data1 = note
        LDA   KBVEL
        ANDA  #$7F             ; 7-bit velocity
        BNE   MONV
        LDA   #$01             ; force >=1 (velocity 0 would read as a note-off on the receiver)
MONV    STA   MDAT2            ; data2 = velocity
        LDA   #$90             ; note-on status $9n
        JSR   MSEND
        RTS

; MONOFF: hook at $A1D2 (was "JSR NOTEOFF" inside KBSERV). Real local note-off, then transmit an INDIVIDUAL
; MIDI note-off ($8n) for the released key - never a blanket All-Notes-Off, so downstream release
; envelopes ring out naturally. Release velocity = $40 (standard). KBKEY=$8421 holds the released key.
; NOTE: uses the CURRENT transpose; changing octave mid-note would mismatch the note-off (rare in play).
MONOFF
        JSR   NOTEOFF
        LDX   #NOTETAB         ; recall the note this key transmitted at note-on
        LDB   KBKEY
        ANDB  #$7F
        LDB   B,X              ; data1 = latched note (matches note-on exactly -> no hang on octave change)
        LDA   #$40             ; data2 = standard release velocity
        STA   MDAT2
        LDA   #$80             ; note-off status $8n
        JSR   MSEND
        RTS

; (MODTX is inlined into KBMIDI above - the mod wheel -> CC1 send, throttled with the pitch read.)

; ================= octave-reset hook (issue: "both buttons -> reset" was blocked by the debounce) =====
; MOCTHK: redirected from the once-per-pass octave scan call ("JSR $AC39" at $98BC). If BOTH Sample
; Upper (panel col 2) and Sample Lower (panel col 7) are held (active-low: bit5 clear), reliably reset
; the octave transpose ($84CD) to 0 and latch the debounce ($84CE) so releasing one button doesn't then
; transpose - then return. Otherwise tail-jump to the stock scan for the normal +/-12 behavior.
PANRD   EQU   SCANC  ; stock panel-column read (writes $E20F col-select, settles, reads back)
OCTSCAN EQU   TPSCAN  ; stock octave-button scan
OCTLAT  EQU   $84CE            ; stock octave debounce latch (cleared by the stock scan on no-button)
MOCTHK
        LDA   #$02
        JSR   PANRD            ; Sample Upper
        ANDA  #$20
        BNE   MOCTSK           ; upper not held -> stock scan
        LDA   #$07
        JSR   PANRD            ; Sample Lower
        ANDA  #$20
        BNE   MOCTSK           ; lower not held -> stock scan
        CLR   MOCTV            ; BOTH held -> reset octave transpose to 0
        LDA   #$01
        STA   OCTLAT           ; latch: releasing one button won't transpose
        RTS
MOCTSK
        JMP   OCTSCAN          ; stock scan (tail-call; its RTS returns to the main loop)

; ===== PRELINIT: boot-time analog DAC init, channels 0-7 =====
; Replaces the leftover stock filter-autotune call (JSR $B96E -> ROM $F571). That routine forced
; resonance=$FF and walked the cutoff DAC to find self-oscillation, then stored one result byte at
; $B050+77n+24 (n=0-7) - addresses inside our OS image. Its analog END state per channel was simply
; VQ=0, VF=0, preload=0, and nothing in our OS ever reads the stored results, so this reproduces the
; entire useful effect with no ROM call, no self-oscillation sweep, and no memory stores.
PRELINIT
        LDB   #$07
PRELLP
        LDX   #$E408
        ABX                     ; X = $E408 + ch
        CLR   ,X                ; VQ (resonance) ch = 0
        CLR   $08,X             ; VF (cutoff) ch = 0
        CLR   $10,X             ; preload DAC ch = 0
        DECB
        BPL   PRELLP
        RTS

; ===== TRIMAP: closed-loop sample-tune multiply (S54) =====
; In/out: A:B = frequency word. Applies word * TRIMV / 128 (TRIMV 78-177 = -858..+561 cents,
; ~13.5 cents/step near unity). Unity ($80) returns immediately. Max input word ~800 (shift-3
; envelope) keeps every intermediate in range: lo*k<<1 carry captured as the 9th bit; hi*k*2 <= 1062.
TRIMAP
        PSHS  A
        LDA   TRIMV
        CMPA  #$80
        PULS  A
        BEQ   TRIMRT            ; unity -> untouched (common case)
        STA   TRTMP             ; hi
        STB   TRTMP+1           ; lo
        LDB   TRIMV
        LDA   TRTMP+1
        MUL                     ; D = lo*k
        ASLB
        ROLA                    ; C:A = (lo*k)>>7
        STA   TRTMP+3
        LDA   #$00
        ROLA                    ; A = ninth bit
        STA   TRTMP+2
        LDA   TRTMP             ; hi
        LDB   TRIMV
        MUL                     ; D = hi*k
        ASLB
        ROLA                    ; D = hi*k*2 (no overflow: hi<=3)
        ADDD  TRTMP+2           ; D = trimmed word
TRIMRT
        RTS

; ===== SMPQSC: capture oscillator quiesce (S56, stock-informed) =====
; The stock sampler puts all 8 voices into a defined quiet state before recording. Ours: zero all 32
; DOC volumes and HALT oscillators 1-31, keeping OSC 0 free-running as the DOC-RAM access provider
; (the historical "pure sine" capture failure came from halting ALL 32 - RAM access needs a running
; oscillator; that old bundle also zeroed the input-filter resonance, which we do NOT touch). Osc 0
; gets wtptr 0 / 32K / freq word $4000: its accumulator+table cycle is tens of ms, so any analog
; coupling of the idle-oscillator cycle into the input path moves far above the audible-wobble band
; (rate-1 captures showed HF dips every ~2.9s - the S45-era seconds-scale family). Bounded OIR drain
; afterwards (halting IE-enabled oscillators flags them). No restore path needed: SMPPLAY rebuilds
; all oscillator state at capture end. Side effect to expect: fewer active fetchers = smaller DOC
; bus stall = capture rates shift toward nominal -> saved sample-tune values need one re-tune.
SMPQSC
        CLRA
        LDX   #$EC40
SMQV
        STA   ,X+               ; volumes, oscs 0-31 = 0
        CMPX  #$EC60
        BCS   SMQV
        LDA   #$01              ; halt (free-run mode, halted, ch0, IE off)
        LDX   #$ECA1
SMQH
        STA   ,X+               ; control regs: oscs 1-30 halted
        CMPX  #$ECBF            ; S57: STOP before osc 31 - the dedicated idle clock stays running
        BCS   SMQH
        CLR   $EC80             ; osc 0 wtptr = page 0 (the 32K buffer)
        LDA   #$38
        STA   $ECC0             ; osc 0: 32K table
        CLR   $EC00             ; osc 0 freq lo = $00
        LDA   #$40
        STA   $EC20             ; osc 0 freq hi = $40 -> word $4000 (fast cycle)
        CLR   $ECA0             ; osc 0: free-run, RUNNING, ch 0, IE off
        LDB   #$20              ; bounded OIR drain (halts above may have flagged)
SMQD
        LDA   $ECE0
        BMI   SMQDD             ; bit7 set = none pending
        DECB
        BNE   SMQD
SMQDD
        RTS

; ===== FCAL: per-channel cutoff ceiling calibration (S85) =====
; A single global CUTMAX has to be safe for the WORST channel, so every other voice gives up
; brightness it did not need: measured on hardware at $C0, two channels self-oscillated (4078 Hz and
; 4422 Hz) while the rest stayed clean. This finds each channel's own onset instead.
; Method, taken from the stock ROM's autotune at $F571: with the VIA port B audio mux set to
; position 0, the DOC's ADC at $ECE2 reads the instrument's own mixed post-filter output (confirmed
; in enmirage.cpp: mux 0 = "compressed and mixed input: audio in and ES 5503", and MAME fakes data
; there specifically "to get past filter calibration"). Drive one channel's cutoff upward with all
; others closed, and watch the ADC swing: silence stays flat, self-oscillation swings hard.
; Port B bits: 0-1 sample-RAM bank, 2-3 audio mux, 4 floppy motor. Only the mux bits are touched and
; port B is restored, so the code window and the drive state are untouched.
; Every loop is bounded and the result is bracketed: a channel that never oscillates keeps CUTMAX,
; and the lowest value that can ever be stored is the sweep floor minus the margin. So the worst
; failure is a slightly dull or slightly bright ceiling, never a hang and never a dead filter.
; Runs at boot before PRELINIT closes everything down; expect a brief chirp as each channel is
; walked into oscillation - the stock OS did exactly the same thing.
FCAL
        LDA   $E200
        PSHS  A                 ; save port B
        ANDA  #$F3              ; audio mux -> 0 (own mixed output); bank and motor bits preserved
        STA   $E200
; S101: close EVERY filter channel before measuring anything. FCAL runs before PRELINIT, so the
; cutoff DACs still hold whatever the boot ROM left in them - if any of those happens to sit above
; its oscillation threshold, the ADC swings no matter which channel is under test and every reading
; is polluted. The sweep's whole premise is "all others silent, one driven".
        LDX   #$E410
        CLRB
FCALCLS
        CLR   B,X
        INCB
        CMPB  #$08
        BCS   FCALCLS
        CLRB                    ; B = channel 0
FCALCH
        LDA   #CUTMAX           ; default if this channel never oscillates
        LDX   #FCEIL
        STA   B,X
; S101: take a BASELINE with this channel still closed. The ADC is reading mux 0 - the mixed input,
; which includes AUDIO IN - so anything connected to the input, or plain noise, swings it. The
; fixed $20 threshold could therefore trip on the very first trial and clamp the ceiling low for the
; whole session, which is exactly the symptom: Viz's measurements imply FCEIL landed at ~140, the
; value produced by detecting oscillation at the first trial. Requiring the swing to exceed the
; channel's own quiet baseline makes the test relative rather than absolute.
        BSR   FCMEAS
        STA   FCBASE
        LDA   #$98              ; sweep floor - below every threshold seen so far
FCALSW
        LDX   #$E410
        STA   B,X               ; drive this channel's cutoff to the trial value
        PSHS  A
        BSR   FCMEAS            ; A = ADC swing over 256 reads
        SUBA  FCBASE            ; S101: swing ABOVE this channel's quiet baseline
        BCS   FCALNH            ; below baseline -> definitely not oscillating
        CMPA  #$20              ; swinging hard = self-oscillating
        PULS  A
        BCC   FCALHIT
        BRA   FCALNX2
FCALNH
        PULS  A
FCALNX2
        ADDA  #$04              ; next trial
        CMPA  #$E0              ; bounded sweep
        BCS   FCALSW
        BRA   FCALNX            ; never oscillated -> keep the CUTMAX default
FCALHIT
        SUBA  #$06              ; S102: margin halved ($0C -> $06). Viz wants maximum range; the
;                                calibration now measures a genuine onset rather than tripping on
;                                input noise, so the old wide margin is no longer earning its keep.
        LDX   #FCEIL
        STA   B,X               ; this channel's ceiling
FCALNX
        LDX   #$E410
        CLR   B,X               ; close the channel again
        INCB
        CMPB  #$08
        BCS   FCALCH
; S86: collapse to the MINIMUM ceiling and give every channel that same value.
; Per-channel ceilings were measured correctly but applied wrongly: with cutoff above the ceiling
; the clamp is active on every voice, so eight different ceilings became eight different timbres.
; Hardware result on unified44 at cutoff 80 / resonance 0, repeated identical A triads: per-strike
; brightness sd 11.5 dB, spread 32.6 dB - and since the allocator rotates voices, that reads as
; arpeggiation and mis-triggering. (Onset spacing measured 770ms +/- 34ms, so the playing and the
; triggering were both fine.) The instrument must sound the same on every voice, so the ceiling has
; to be uniform; the calibration still earns its keep by MEASURING that ceiling instead of guessing
; it, and by adapting to whatever this particular unit's worst channel actually does.
        LDX   #FCEIL
        LDA   ,X                ; A = running minimum
        LDB   #$07
FCMINL
        CMPA  B,X
        BLS   FCMIN1
        LDA   B,X               ; lower -> new minimum
FCMIN1
        DECB
        BNE   FCMINL
        LDB   #$07
FCMINW
        STA   B,X               ; every channel gets the safe minimum
        DECB
        BPL   FCMINW
        PULS  A
        STA   $E200             ; restore port B
        RTS

; FCMEAS: ADC peak-to-peak over 256 reads -> A. The reads outrun the DOC's ~31us conversion, so
; roughly every third one is fresh; 256 of them span ~3ms, which is a dozen cycles of a 4kHz
; oscillation - plenty to separate a swinging channel from a silent one.
FCMEAS
        PSHS  B
        LDA   #$FF
        STA   FCMIN
        CLR   FCMAX
        CLRB                    ; 256 iterations
FCMLP
        LDA   $ECE2
        CMPA  FCMIN
        BCC   FCM1
        STA   FCMIN
FCM1
        CMPA  FCMAX
        BLS   FCM2
        STA   FCMAX
FCM2
        DECB
        BNE   FCMLP
        LDA   FCMAX
        SUBA  FCMIN
        PULS  B
        RTS

; ===== SUSREL: pedal lifted - release every voice we parked in state $05 (S89) =====
SUSREL
        LDU   #VBASE
        CLRB
SUSR1
        LDA   OAST,U
        CMPA  #$05
        BNE   SUSR2
        LDA   #$04
        STA   OAST,U
        STA   OFST,U
        STA   OPST,U
SUSR2
        LEAU  VSTRIDE,U
        INCB
        CMPB  #$08
        BNE   SUSR1
        RTS

; ===== SUSCC: transmit MIDI CC64 (sustain) with the value in A (S90) =====
; Same shape as the inlined CC1 send in KBMIDI. Stock emits $7F on pedal-down and $00 on pedal-up.
SUSCC
        STA   MDAT2             ; data2 = value
        LDB   #$40              ; data1 = controller 64 (sustain)
        LDA   #$B0              ; control-change status $Bn
        JMP   MSEND

; ===== PBAPPLY: FREQADJ = FREQADJ + (FREQADJ * PBDEV)/1024   (S91) =====
; A proportional bend, so it is musically even across the keyboard. The divisor 1024 puts the wheel's
; full ~127 counts of travel at about +/-200 cents, which makes one ADC count ~1.5 cents - matching
; the wheel's own resolution instead of throwing 3 bits of it away as S89-S90 did.
; The 24-bit product is formed as two MULs; the >>8 is taken for free by keeping only the upper
; bytes, leaving just a >>2 to do. FREQADJ is stored lo-first, so it is loaded and stored bytewise.
PBAPPLY
        LDA   PBDEV
        BPL   PBA1
        NEGA
PBA1
        STA   PBMAG             ; |deviation|
        LDA   FREQADJ+1         ; word hi
        LDB   PBMAG
        MUL                     ; D = hi*mag
        STD   PBTMP
        LDA   FREQADJ           ; word lo
        LDB   PBMAG
        MUL                     ; D = lo*mag
        TFR   A,B               ; (lo*mag) >> 8
        CLRA
        ADDD  PBTMP             ; D = (word*mag) >> 8
        LSRA
        RORB
        LSRA
        RORB                    ; D = (word*mag) >> 10, the offset at the REFERENCE range (+/-2 st)
        STD   PBTMP
; S108: scale to the selected range. The reference slope is 8, so the result is offset*slope/8,
; formed as a 16x8 multiply whose 24-bit product is shifted back by 3. A wide UP bend legitimately
; wants up to 4x the frequency word, which cannot fit 16 bits on a high note, so it SATURATES - a
; limit of the register, not of this code, and worth stating on the parameter card.
        LDA   PBTMP             ; offset high byte
        LDB   PBSLP
        MUL                     ; D = H
        CMPD  #$0800
        BCC   PBSATU            ; H<<5 would not fit -> saturate
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA                    ; D = H << 5
        STD   PBACC
        LDA   PBTMP+1           ; offset low byte
        LDB   PBSLP
        MUL                     ; D = L
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D = L >> 3
        ADDD  PBACC
        BRA   PBSCD
PBSATU
        LDD   #$FFFF
PBSCD
        STD   PBTMP
        LDA   FREQADJ+1
        LDB   FREQADJ           ; D = word
        TST   PBDEV
        BMI   PBASUB
        ADDD  PBTMP
        BRA   PBAST
PBASUB
        SUBD  PBTMP
PBAST
        STA   FREQADJ+1
        STB   FREQADJ
        RTS

; ===== PBCALC: derive the bend deviation from the current wheel reading (S98) =====
; Lifted out of SYNCP unchanged. It lived there only because SYNCP happens to run every pass; its
; real dependency is PBRAW, so it belongs immediately after WHEELRD. At WHDIV = 1 both ran once per
; pass, so this move is behaviour-neutral - and it frees SYNCP to become conditional, which is the
; actual goal: SYNCP spends about 5.4ms of the ~30ms loop in PFIND table scans alone.
PBCALC
; S90: compute the deviation as an UNSIGNED magnitude plus a direction. The S89 version used a signed
; SUBA, which underflows whenever the wheel's calibrated rest position sits above mid-scale: once the
; wheel goes far enough down, PBRAW - PBCEN wraps from a large negative value to a positive one and
; the pitch JUMPS UP instead of continuing down. Hardware-measured on unified48: bending down carried
; the chord 543 -> 293 Hz and then snapped back to 366 Hz and stuck there.
; S91: keep the FULL 8-bit deviation. S89-S90 divided it by 8 and added it to the 8-bit trim factor,
; where one step is 13.5 cents - that quantisation, not jitter, is the "coarse" bend Viz hears.
; PBAPPLY now scales the frequency word by dev/1024 instead, so one ADC count is ~1.5 cents on the
; boot wave: the wheel's own 8-bit resolution becomes the limit, as it should be.
        LDA   PBRAW
        CMPA  PBCEN
        BCC   PBUP              ; at or above rest -> bend up
        LDA   PBCEN
        SUBA  PBRAW             ; magnitude only - cannot wrap
        JSR   PBHYST            ; S169: hysteretic dead band, A preserved
        BLS   PBNONE
; S92: clamp before negating. NEGA of a magnitude above 127 wraps back to a POSITIVE value, so the
; deepest part of a down-bend flipped up: measured on unified50 as -196 cents jumping to +200. The
; S90 fix removed the wrap from the SUBTRACTION; this removes it from the NEGATION.
        CMPA  #$7F
        BLS   PBNEG
        LDA   #$7F              ; full down-bend
PBNEG
        NEGA                    ; ...applied downwards
        BRA   PBLOC
PBUP
        SUBA  PBCEN             ; magnitude only - cannot wrap
        JSR   PBHYST            ; S169: hysteretic dead band, A preserved
        BLS   PBNONE
        BRA   PBLOC
PBLOC
        CLR   MBACT            ; S149: the local wheel is off rest, so it takes ownership back
        BRA   PBSTO
PBNONE
; S149: the wheel is at rest. Previously this ZEROED PBDEV unconditionally, every single pass - and
; because PBCALC runs from KBMIDI, which the main loop calls AFTER MIDIN, any bend just received over
; MIDI was erased within the same pass. That is why MIDI notes worked and MIDI bend did not: notes
; are acted on immediately, bend is state that persists and was being clobbered.
; Now, if MIDI has sent a bend and the local wheel is not being used, the MIDI value is adopted here
; and falls through the SAME code the wheel uses - so it gets the correct up/down slope for the
; selected bend range and the same PBACT handling. MIDBEND could not do that itself: it set PBDEV and
; PBACT but never PBSLP, so even a surviving deviation would have been scaled by a stale slope.
        TST   MBACT
        BEQ   PBNZERO
        LDA   MBDEV             ; MIDI owns the bend while the wheel sits at rest
        BRA   PBSTO
PBNZERO
        CLRA                    ; at rest and no MIDI bend -> no bend
PBSTO
        STA   PBDEV
; S108: choose this note's bend slope now, while the direction is known, so PBAPPLY needs no test.
; Bend is exponential in semitones but the offset is linear in wheel position, so the directions need
; DIFFERENT slopes: at +/-12 semitones the pitch must rise by the whole frequency word but fall by
; only half of it - one symmetric slope would subtract the entire word and stop the oscillator.
        PSHS  A
        LDA   #SP_PBR
        JSR   PFIND
        DECA                    ; range 1-24 -> table index 0-23
        LDX   #PBRUP
        TST   PBDEV
        BPL   PBCUP
        LDX   #PBRDN
PBCUP
        LDB   A,X
        STB   PBSLP
; S110: no RPN announcement. MIDI bend is normalised - the RECEIVER owns the semitone range - so
; matching it means either RPN 0 or nothing. Deferred until a receiver actually needs it; the code
; is in the S109 notes if so.
        PULS  A
        BEQ   PBIDLE
        LDB   #$04
        STB   PBACT             ; bent: keep the frequency writer running
        BRA   PBDONE
PBIDLE
        TST   PBACT
        BEQ   PBDONE
        DEC   PBACT             ; linger, so the return to centre gets written out
PBDONE
        RTS

; ===== PSYNC: run SYNCP only when the parameters have actually changed (S99) =====
; SYNCP re-reads ~40 parameters every pass and each PFIND scans PARMTAB linearly, which measures at
; about 5.4ms of the ~30ms main loop - and the loop period is what limits wheel resolution, filter
; refresh drain and general responsiveness. Almost every pass re-derives values that did not move.
; DETECTION BY CHECKSUM, not by a dirty flag. A flag has to be set by every writer, and missing one
; would leave the engine silently stale - a horrible intermittent bug. A checksum cannot be bypassed
; by any writer, present or future. Only the VALUE byte of each entry can change (spec/min/max are
; fixed at build time), so summing 45 bytes with a stride of 4 costs ~630 cycles, about 0.34ms - an
; eighth of what it saves.
; A sum can in principle miss compensating edits (+1 here, -1 there in the same pass), which single
; parameter editing cannot produce; the forced resync below covers that case anyway.
; SAFETY NET: resync unconditionally every 32 passes (~1s) regardless of the checksum, so any
; hidden dependency - something outside SYNCP writing an engine variable it owns - can drift for at
; most a second instead of indefinitely.
PSYNC
        LDX   #PARMTAB+1        ; the value byte of entry 0
        LDB   #NPARM2           ; 45 entries
        CLRA
PSUMLP
        ADDA  ,X                ; sum the value bytes only
        LEAX  $04,X             ; ...stride one entry
        DECB
        BNE   PSUMLP
        CMPA  PSUMLST
        BNE   PSYNCGO           ; something moved -> sync
        DEC   PSYNCC
        BNE   PSYNCSK           ; nothing moved and the timer has not expired -> skip
PSYNCGO
        STA   PSUMLST
        LDA   #$20              ; 32 passes until the next forced resync
        STA   PSYNCC
        JMP   SYNCP             ; tail call
PSYNCSK
        RTS

; ===== SMPREV: reverse the 32K sample buffer in place (S112) =====
; DOC sample RAM is directly addressable at $0000-$7FFF - the boot wave generator writes straight to
; it - so this is a plain byte-swap from both ends towards the middle: 16384 swaps, a few hundred
; milliseconds, once per toggle. Playback needs no changes at all, which is what makes reverse cheap
; on this hardware: the ES5503 cannot play backwards, but it does not need to.
; A reverse LOOP comes free with it - reverse the data, then loop as normal.
; ===== S222b: SCRUB EVERY $00 OUT OF THE SAMPLE BUFFER WHEN LOOPING =====
; Build 155 would not loop: the note played once and stopped. Forensics on Viz's
; calibration disk found why, in data we already had. All three slots carry
; LMODE = 1 and SENDPOS = 0 - the OS believes no end marker is placed - yet each
; buffer still holds a run of exactly 8 zero bytes, at $7FD9, $7FF8 and $7FDE.
; CAPTURE writes its end marker at a BYTE-PRECISE offset. SENDPOS stores only the
; HIGH byte of an offset, so the S126 removal path can address 256-byte boundaries
; and nothing else: it can NEVER remove a marker that capture placed. Under the
; pager that was survivable - the halt merely looked like an extra page swap (the
; S150 note) - but free-run halts outright on a $00 (es5503.cpp: read_byte == 0 ->
; halt_osc(type 1) -> control |= 1), so the note dies there. That is build 155.
; The fix does not try to be clever about positions: it removes every $00 from the
; buffer, which is the same $00 -> $01 substitution capture already applies to the
; rest of it. One LSB, inaudible. ~33k bytes at ~6 cycles is well under 100 ms and
; it runs once per loop-on transition, not per note and not per parameter pass.
; The normal SENDHAVE bookkeeping still runs afterwards, so a marker that WAS
; recorded in SENDPOS is still restored properly from SENDSV8 rather than left at $01.
LPZSCRB
        TST   LPSCRB
        BNE   LPZRET            ; already scrubbed for this loop-on
        PSHS  A,X
; S234d: an OS-placed end marker must be RESTORED first, not scrubbed. Scrubbing turned its
; 8 zeros into $01 while SENDPOS still said "placed"; the same position on the next pass
; matched SENDHAVE's unchanged-check, so it was never re-placed - each loop-on lost the
; marker and playback ran on (Viz, 186: '2 3-' -> '2 3 4-' -> '2 3 4 5' on loop toggles).
; Restore + forget it; ENDMK re-places it from scratch later in this same sync pass.
        LDA   SENDPOS
        BEQ   LPZGO
        PSHS  B,Y,U             ; SRESTORE trashes A,B,X,U; U is live across SYNCP
        JSR   SRESTORE
        CLR   SENDPOS
        PULS  B,Y,U
LPZGO
        LDX   #$0000            ; DOC sample RAM is directly CPU-addressable (as SMPREV)
LPZLP
        LDA   ,X
        BNE   LPZNXT
        LDA   #$01
        STA   ,X                ; $00 is the only byte the DOC treats as "stop"
LPZNXT
        LEAX  $01,X
        CMPX  #$8000
        BNE   LPZLP
        LDA   #$01
        STA   LPSCRB
        PULS  A,X
LPZRET
        RTS

SMPREV
        PSHS  X,U
        LDX   #$0000
        LDU   #$7FFF
SMPRVL
        LDA   ,X
        LDB   ,U
        STB   ,X+
        STA   ,U
        LEAU  -1,U
        CMPX  #$4000
        BLO   SMPRVL
        PULS  X,U
        RTS

; ===== S226: REVRNG - reverse DOC RAM [X..U] in place (SMPREV generalized) =====
; X = first byte, U = last byte (inclusive). Clobbers A,B,X,Y,U. Same DOC-RAM direct
; addressability rule as SMPREV/LPZSCRB (an oscillator is always running in the states
; that reach this - the same states those two are proven in).
REVRNG
        PSHS  X
        TFR   U,D
        SUBD  ,S++              ; D = last - first
        ADDD  #$0001
        LSRA
        RORB                    ; D = swap count (len>>1)
        TFR   D,Y
        LEAY  ,Y                ; TFR sets no flags; LEAY does -> Z if empty
        BEQ   REVRT
REVLP
        LDA   ,X
        LDB   ,U
        STB   ,X+
        STA   ,U
        LEAU  -1,U
        LEAY  -1,Y
        BNE   REVLP
REVRT
        RTS

; ===== S227: ROTSYNC - request rotation A (pages), deferred while the target moves =====
; The S226c defer: walk only when the same target arrives on two consecutive sync passes
; (after edits stop, the <=1s forced resync is the second pass). Shared by the loop branch
; (A = LSTART) and the one-shot branch (A = SSTART) of SYNCP.
ROTSYNC
        CMPA  ROTPG
        BEQ   ROTSRT            ; already there -> nothing to do
        CMPA  LSDES
        BEQ   ROTSGO            ; stable across two syncs -> walk now
        STA   LSDES             ; still moving -> remember it and wait
        RTS
ROTSGO  JMP   ROTAPPLY          ; tail call: removes any OS marker, walks, updates ROTPG
ROTSRT  RTS

; ===== S226: ROTAPPLY - set the buffer's absolute rotation to A (512B pages, 0-63) =====
; Rotates the 32K sample LEFT by (A - ROTPG) mod 64 pages via triple reversal
; (rot(S) = rev(0,S-1) + rev(S,N-1) + rev(0,N-1)) - no scratch page, ~1s full walk,
; each byte moved twice. Any OS-placed end marker is restored FIRST (its physical
; position is about to move); the caller's marker machinery re-places it afterwards.
; Clobbers A,B,X,Y,U + SENDPOS state. Callers: SYNCP loop section, loop-off, reverse
; toggle, save entry.
ROTAPPLY
        PSHS  Y,U               ; U is LIVE across the SYNCP param section (the SENDHAVE
                                ; machinery preserves it around SRESTORE - same rule here);
                                ; Y for the same insurance. X is PFIND-trashed by convention.
        PSHS  A                 ; [S] = new absolute rotation
        LDA   SENDPOS
        BEQ   ROTAP1
        JSR   SRESTORE          ; put the 8 saved bytes back (trashes A,B,X,U)
        CLR   SENDPOS
ROTAP1
        LDA   ,S
        SUBA  ROTPG
        ANDA  #$3F              ; delta pages 0-63
        BEQ   ROTAPD            ; nothing to move (marker already restored is fine:
;                                 the sync pass that called us re-places it)
        ASLA                    ; A = delta*2 = high byte of the byte span S (2..126)
        PSHS  A                 ; [S] = S-hi, 1,S = new rotation
        SUBA  #$01
        LDB   #$FF
        TFR   D,U               ; U = S-1
        LDX   #$0000
        JSR   REVRNG            ; rev(0, S-1)
        LDA   ,S
        CLRB
        TFR   D,X               ; X = S
        LDU   #$7FFF
        JSR   REVRNG            ; rev(S, 32767)
        LDX   #$0000
        LDU   #$7FFF
        JSR   REVRNG            ; rev(0, 32767)
        LEAS  1,S               ; drop S-hi
ROTAPD
        PULS  A
        STA   ROTPG
        PULS  Y,U
        RTS

; ===== MIDIRQ: FIRQ handler - one received byte into the ring (S127) =====
; FIRQ stacks only PC and CC, so everything used must be saved by hand. Kept deliberately short:
; read status, read data (which clears RDRF), store, return. All interpretation happens in the main
; loop, where it cannot delay the next byte.
MIDIRQ
        PSHS  A,B,X
        LDA   $E100             ; ACIA status
        LDB   $E101             ; always read the data register - that is what clears RDRF, overrun
                                ; and framing errors
        BITA  #$01              ; was it actually a received byte?
        BEQ   MIRQX
; S231: realtime bytes ($F8-$FF: clock, start/stop, active sensing) never enter the ring.
; MIDIN discarded them anyway; an arpeggiator's 24ppqn clock was spending ring slots.
        CMPB  #$F8
        BCC   MIRQX
        LDX   #MIRING
        LDA   MIRHD
        STB   A,X               ; signed 8-bit index around the ring centre (S231)
        INCA                    ; wraps $FF->$00 by itself: 256-byte ring, no mask
        CMPA  MIRTL
        BEQ   MIRQX             ; ring full -> drop this byte rather than lapping the reader
        STA   MIRHD
MIRQX
        PULS  A,B,X
        RTI

; ===== MIDIN: drain and interpret, called from the main loop (S127) =====
; Handles RUNNING STATUS, which sequencers lean on heavily - a parser without it appears to work on
; some sources and fails on others. Note-on with velocity zero is treated as note-off, the other
; classic trap. Messages on other channels are parsed and discarded, so their data bytes cannot be
; mistaken for ours.
MIDIN
        LDA   MIRTL
        CMPA  MIRHD
        BEQ   MIDINR            ; ring empty
        LDX   #MIRING
        LDB   A,X               ; B = next byte (signed index around the centre, S231)
        INCA                    ; natural 8-bit wrap = 256-byte ring (S231)
        STA   MIRTL
        TSTB
        BPL   MIDATA            ; bit7 clear -> data byte
; --- status byte ---
        CMPB  #$F8
        BCC   MIDIN             ; $F8-$FF realtime: ignore entirely, they may interleave anywhere
        CMPB  #$F0
        BCC   MIDSYS            ; $F0-$F7 system common: drop running status and skip
        STB   MISTAT            ; channel message -> becomes the running status
        CLR   MICNT
        BRA  MIDIN
MIDSYS
        CLR   MISTAT
        CLR   MICNT
        BRA  MIDIN
; --- data byte ---
MIDATA
        LDA   MISTAT
        BEQ   MIDIN             ; data with no status yet -> nothing to do
        TST   MICNT
        BNE   MIDAT2X
        STB   MIDAT1            ; first data byte
        INC   MICNT
; two-byte messages complete on the first data byte
        LDA   MISTAT
        ANDA  #$F0
        CMPA  #$C0
        BEQ   MIDDONE           ; program change
        CMPA  #$D0
        BEQ   MIDDONE           ; channel pressure
        BRA  MIDIN
MIDAT2X
        CLR   MICNT             ; second data byte completes the message; running status persists
        LDA   MISTAT
        ANDA  #$0F              ; CHANNEL nibble of the status byte - NOT a ring index.
                                ; (S228c: the S228b ring-mask sweep blindly converted this
                                ; to #$1F; bit 4 of $9n/$Bn survived, no message ever
                                ; matched MOCHAN, and ALL MIDI receive died. The count-
                                ; assert matched but the CONTEXT was never checked - the
                                ; standing scripted-edit rule, paid for again.)
        CMPA  MOCHAN
        BNE   MIDIN             ; not our channel -> consumed, but ignored
        LDA   MISTAT
        ANDA  #$F0
        CMPA  #$90
        BEQ   MIDNON
        CMPA  #$80
        BEQ   MIDNOFF
        CMPA  #$E0
        BEQ   MIDBEND
        CMPA  #$B0
        BEQ   MIDCC             ; S208: control change - CC64 sustain is honored
        LBRA MIDIN
MIDDONE
        CLR   MICNT
        LBRA MIDIN
MIDINR
        RTS

; --- note on: MIDI note -> our key index, inverting exactly what MONON transmits ---
; MONON sends  note = KBKEY + NOTEOFS + MTUNE + MOCTV, so receive takes the same route backwards.
; That way a note played here and the same note arriving over MIDI sound at the same pitch, and the
; octave buttons and coarse transpose track on both.
MIDNON
        TSTB
        BEQ   MIDNOFF           ; velocity 0 IS a note-off - the classic trap
; S147: PRESERVE the local keyboard's in-progress note. KBSERV is a STATE MACHINE spread across
; several main-loop passes: one pass stores the key byte into KBKEY and sets KBST=2, a later pass
; receives the velocity byte and only then calls NOTEON. MIDIN runs in that same loop, so a MIDI
; note arriving between those two passes OVERWROTE KBKEY - the local note then sounded the MIDI
; note's pitch, and releasing the local key computed the ORIGINAL key, matched no voice, and left
; the wrongly-sounded note STUCK. That is exactly the fault seen playing the keyboard against an
; external arpeggiator, and it can only occur when both sources are active at once.
        LDA   KBKEY
        PSHS  A
        LDA   KBVEL
        PSHS  A
        JSR   MIDKEY            ; S226R: shared MIDI key translate -> KBKEY
        TFR   B,A
        STA   KBVEL             ; MIDI velocity is already 0-127, the same scale KBVEL uses
        JSR   NOTEON            ; the local voice path, unchanged - MIDI and keyboard share the voices
        PULS  A
        STA   KBVEL             ; S147: hand the local state machine its note back
        PULS  A
        STA   KBKEY
        LBRA  MIDIN
MIDNOFF
        LDA   KBKEY             ; S147: the same race applies to the note-off path
        PSHS  A
        JSR   MIDKEY            ; S226R: shared MIDI key translate -> KBKEY
        JSR   NOTEOFF
        PULS  A
        STA   KBKEY             ; S147: restore the local state machine's key
        LBRA  MIDIN
; --- pitch bend: 14-bit -> the same PBDEV the wheel drives, so both feel identical ---
MIDBEND
        TFR   B,A               ; B = MSB (data2); the LSB in MIDAT1 is below our resolution
        SUBA  #$40              ; centre $40 -> signed -64..+63
        ASLA                    ; -> roughly -128..+126, the range PBDEV uses
; S149: hand the value to PBCALC rather than writing PBDEV directly. PBCALC then applies the bend
; range slope and the PBACT linger exactly as it does for the wheel, so MIDI bend and wheel bend
; behave identically - including parameter 73.
        STA   MBDEV
        LDA   #$01
        STA   MBACT
        LBRA  MIDIN
; --- control change (S208): only CC64 (sustain) is honored; every other CC is consumed and
; ignored, so its data bytes can never desync the parser. Mirrors the local pedal ($B8/$B9 in
; KBSERV) exactly, EXCEPT there is no SUSCC transmit - echoing a received CC64 back out would
; loop with the sender. B = data2 here (0-127); MIDI convention: 0-63 = up, 64-127 = down.
MIDCC
        LDA   MIDAT1
        CMPA  #$40              ; CC 64 = sustain pedal?
        BNE   MIDCC1
        CMPB  #$40
        BCS   MIDSUSU           ; data2 < 64 -> pedal up
        STB   SUSTAIN           ; nonzero (64-127) = pedal down
        LBRA  MIDIN
MIDSUSU
        CLR   SUSTAIN
        JSR   SUSREL            ; release everything held - the same routine the local pedal-up uses
        LBRA  MIDIN
; --- S227b: CC 1 = MOD WHEEL. The whole wheel-editing system over MIDI, so rackmount
; owners (no local wheel) get param editing and the LFO-destination functions from any
; keyboard's wheel. The received value is treated as an EXTERNAL EDIT of the wheel's
; target param: MWLASTV is deliberately NOT updated, so a keyboard unit's local wheel
; re-baselines (the existing keypad-edit mechanism) instead of yanking the value back -
; whoever moved last wins, and a resting wheel never fights. No echo: our own CC1
; transmit keys off the local ADC, not off param writes, so two Mirages can face each
; other without a loop. The local bend-gate is analog-bleed insurance and does not apply
; to a digital value, so it is not consulted here.
MIDCC1
        CMPA  #$01
        BNE   MIDCCX            ; every other CC: consumed and ignored (parser stays synced)
; S228b: LATCH ONLY. A dense wheel sweep is hundreds of messages; doing the PFIND + map
; work per message stretched the main-loop pass while the FIRQ ring kept filling, and
; dropped bytes = dropped note-offs = Viz's hanging notes. The parser now just latches
; the newest value; CC1SRV applies it ONCE per pass - the same cost the local wheel has.
        ASLB                    ; data2 0-127 -> 0-254, the wheel's own scale
        STB   CC1VAL
        LDB   #$01
        STB   CC1PEND
MIDCCX
        LBRA  MIDIN

; ===== S226R shared idioms (dead-weight reclaim for the S226 rotate) =====
; FSH6: D = FREQADJ word >> 6 (the vibrato/pitch-env/fine-tune "t = freq>>6" idiom).
; MSH6: D = (A*B) >> 6 (the MUL-then->>6 idiom: filter env/res terms, LFO scale, APKVS,
; SCALERES, RELKCALC). Both clobber only A,B; the caller's next-op flag use survives
; because the final RORB still sets CC and JSR/RTS do not touch it.
FSH6
        LDA   FREQADJ+1
        LDB   FREQADJ
        BRA   SH6
MSH6
        MUL
SH6
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D >>= 6
        RTS

; SCALEW (S234b): the one frequency-word scaler both pitch paths call (note-on, VIBWRF).
; A sample -> SMPSCALE (rate shift + sample tune), exactly as before. The BOOT SAWTOOTH -> a fixed
; trim of SAWK/256: Viz measured the default saw 145 cents SHARP with a tuner-verified reference
; (sampled notes are right - TRIMBTB is anchored by tuner). The freqtab anchor (S74) was set by
; ear during the sharp-reference period; retuning the table itself would move every sample rate,
; so only the saw is trimmed. SAWK 236 = 0.92188 = -144.4c (residual +0.6c). Clobbers A,B.
SAWK    EQU   236
SCALEW
        TST   SMPRDY
        BNE   SMPSCALE          ; sample loaded -> the existing path (its RTS returns to our caller)
        LDA   FREQADJ           ; word lo
        LDB   #SAWK
        MUL                     ; A = (lo*k)>>8
        PSHS  A
        LDA   FREQADJ+1         ; word hi
        LDB   #SAWK
        MUL                     ; D = hi*k = (hi<<8)*k>>8
        ADDB  ,S+
        ADCA  #$00              ; D = word*k>>8 (< word: no overflow)
        STA   FREQADJ+1
        STB   FREQADJ
        RTS

; SMPSCALE (S226R): sample-mode rate scaling, shared by note-on and the VIBWRF tick path.
; FREQADJ >>= SMPSHFT (clamped 0-7; corrupt state can only mistune, never hang), then TRIMAP
; (param 6 sample tune), result back into FREQADJ. Clobbers A,B,NSHCNT. Callers guard on SMPRDY.
SMPSCALE
        LDB   SMPSHFT
        ANDB  #$07              ; (S228b: the S227 rate-1 halving is GONE - rate-1
        STB   NSHCNT            ; one-shots play at true resshift 10 via the 16K pair)
        LDA   FREQADJ+1         ; freq hi
        LDB   FREQADJ           ; freq lo
        TST   NSHCNT
        BEQ   SMPSCD            ; shift 0 (full-rate capture) -> word unchanged
SMPSCL
        LSRA
        RORB
        DEC   NSHCNT
        BNE   SMPSCL
SMPSCD
        JSR   TRIMAP            ; S54: per-sample tune (param 6)
        STA   FREQADJ+1
        STB   FREQADJ
        RTS

; MIDKEY (S226R): MIDI note number -> local key space -> KBKEY (shared by MIDNON/MIDNOFF).
MIDKEY
        LDA   MIDAT1
        SUBA  #NOTEOFS
        SUBA  MTUNE
        SUBA  MOCTV
        ANDA  #$7F
        STA   KBKEY
        RTS

; ===== FINEAPP: X -> freqtab entry. Writes FREQADJ = base word with fine tune applied. (S153) =====
; Extracted so that BOTH the note-on path and VIBGO use it. VIBGO recomputes the frequency from the
; table on EVERY main-loop pass to apply vibrato and the pitch envelope, and it applied the base
; note, coarse tune and transpose - but NOT the fine tune. So note-on set the fine adjustment
; correctly and VIBGO wiped it about 9ms later, which is why parameter 13 had no audible effect on
; any note, sampled or synth. One routine now serves both, so they cannot drift apart again.
FINEAPP
        LDA   1,X               ; freq hi
        LDB   ,X                ; freq lo
        STA   FREQADJ+1         ; FREQADJ+1 = hi  (base word, lo-first)
        STB   FREQADJ           ; FREQADJ = lo
        LDA   TUNEFIN
        BEQ   FINERT            ; fine=0 -> no adjustment
; t = freq >> 6  (D = freq value hi:lo)
        JSR   FSH6            ; S226R: FREQADJ>>6 shared. D = freq>>6 ; A~0, B=t
        LDA   TUNEFIN
        BPL   FINEABS
        NEGA
FINEABS
        MUL                     ; D = t * |fine|
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB
        LSRA
        RORB                    ; D = delta
        STD   FREQADJ           ; stash delta in FREQADJ temporarily (interrupt-safe, no stack)
        LDA   TUNEFIN
        BPL   FINEPADD
; negative: base - delta
        LDA   1,X               ; base hi (X still -> freqtab entry)
        LDB   ,X                ; base lo -> D = base
        SUBD  FREQADJ           ; base - delta
        BRA   FINEPUT
FINEPADD
        LDA   1,X               ; base hi
        LDB   ,X                ; base lo -> D = base
        ADDD  FREQADJ           ; base + delta
FINEPUT
        STA   FREQADJ+1         ; adjusted hi
        STB   FREQADJ           ; adjusted lo  (lo-first)
FINERT
        RTS

; ===== GENWAVE: (re)build the default sawtooth into DOC RAM $0000 (S156) =====
; Lifted out of the boot sequence so that loading an EMPTY slot can restore the default wave. It was
; previously inline and reachable only at power-on, which meant that once a sample had been captured
; there was no way back to the synth wave short of a power cycle.
GENWAVE
; ---- generate a band-limited SAWTOOTH into DOC RAM $0000 (S113) ----
; A sawtooth as an ASYMMETRIC TRIANGLE: a long linear rise, then a short linear fall over 1024 of
; the 32768 samples. Its harmonic amplitudes go as sinc(n/32)/n - i.e. a sawtooth's own 1/n law up
; to about the 32nd harmonic, rolling off above it. That roll-off is the point: a RAW ramp carries
; harmonics to 16384, and since the DOC decimates this table heavily to reach audible pitches,
; everything above the output Nyquist would fold back as inharmonic noise. Limiting to ~32 keeps it
; clean across the keyboard while giving the filter far more to work with than the three harmonics
; (1, 1/2, 1/4) this replaces.
; It is also much cheaper: two linear ramps at ~10 cycles per sample instead of three sine lookups
; and three phase accumulators at ~114, so boot-time generation drops from about 2.0s to 0.2s.
; The 256-byte sine table goes with it - nothing else used it.
        LDY   #$0000             ; DOC RAM dest (32768-aligned)
        LDX   #$0100             ; 8.8 accumulator; the high byte is the sample value
GENRIS
        TFR   X,D
        TSTA
        BNE   GENR1
        LDA   #$01               ; never emit $00 - free-run halts on it
GENR1
        STA   ,Y+
        LEAX  2,X                ; rise: 31744 steps of 2 -> $0100 to $F900
        CMPY  #31744
        BNE   GENRIS
GENFAL
        TFR   X,D
        TSTA
        BNE   GENF1
        LDA   #$01
GENF1
        STA   ,Y+
        LEAX  -62,X              ; fall: 1024 steps of 62 -> back to $0100
        CMPY  #$8000
        BNE   GENFAL
        RTS

; ===== PBHYST: hysteretic pitch-wheel dead band (S169) =====
; A = wheel displacement magnitude. Returns with the carry set if it should be treated as REST.
; A single fixed threshold of 8 made the wheel chatter when it happened to rest right at the edge:
; the reading flipped either side of 8 and the engine flipped between "no bend" and "bend of -8",
; transmitting a pitch-bend message on every flip. Viz saw a steady alternating stream of
; E0 40 3B / E0 00 40 - 7680 and 8192 - with the wheel untouched.
; Two thresholds fix it without adding any lag to a real bend: it takes 12 counts to LEAVE rest but
; only 6 to stay bending, so a wheel sitting anywhere between cannot oscillate.
; CC survives RTS on the 6809, so the caller branches on the comparison made here.
PBHYST
; S171: A IS THE WHEEL DISPLACEMENT AND MUST SURVIVE. S169 loaded the threshold into A and returned
; with it there, so the caller used 12 or 6 as the displacement instead of the real position - a full
; sweep transmitted nothing but +/-6 and +/-12, which is exactly the coarse ladder Viz logged
; ($3A $3D $40 $43 $46 and nothing between). The threshold now lives in B, A is untouched, and the
; caller branches on BLS exactly as the original fixed-threshold code did.
; PSHS and PULS do not disturb the condition codes on the 6809, so the comparison survives the
; restore and can be branched on after the RTS.
        PSHS  B
        LDB   #$0C              ; leaving rest needs 12
        TST   PBDEV
        BEQ   PBHY1
        LDB   #$06              ; already bending: stay until it falls below 6
PBHY1
        PSHS  B
        CMPA  ,S+               ; displacement - threshold
        PULS  B
        RTS

