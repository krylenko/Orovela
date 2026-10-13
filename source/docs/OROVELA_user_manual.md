<!--
OROVELA USER MANUAL — TEXT SOURCE. Edit this file, then run:  python3 make_manual.py
(make_manual.py reads this file; nothing in the Python needs touching for text changes.)

Format rules:
  version: / footer:      header-right text and page-footer text
  # PANEL <title>         one button close-up; buttons are drawn as a VERTICAL strip,
                          top to bottom in the order listed. Up to 4 panels; they sit on
                          the 4-column grid left to right.
    - LEGEND | TAG | small text      one button: printed legend, green Orovela tag, sub-label
                                     (leave TAG empty, e.g. "- UPPER | |", for no tag)
    both: TEXT | small text          green "press together" tag under the strip
  # NOTE <title>          a text box in a panel slot instead of buttons (plain lines)
  # COLUMN                starts the next text column (4 columns on the page)
  ## Heading              green section band
  ### Heading             green subhead
  plain lines             paragraph (consecutive lines join; blank line ends it)
  1. text                 numbered step (any number; renumbered automatically)
  - text                  bullet
  > text                  shaded tip box
  **bold**                bold
  Characters: use - not the long minus; ±, ·, × are fine.
-->
version: Orovela 1.5 · 2026-10-13
footer: Every parameter, range and default: see the Orovela Parameter Reference card.

# PANEL SEQ
- REC | SAMPLE | arm / record
- PLAY | PANIC | press twice
- LOAD | LOAD PROG | slot 0-9, Enter
- SAVE | SAVE PROG | slot 0-9, Enter

# PANEL SAMPLE
- UPPER | OCTAVE + | up to +2
- LOWER | OCTAVE - | down to -2
both: BOTH = OCTAVE RESET |

# PANEL LOAD
- UPPER | |
- LOWER | |
both: BOTH = RESET PARAMS | press together; alone they do nothing

# NOTE READING THE PANELS
White = the legend printed on the Mirage.
Green = what the button does in Orovela.
PARAM, VALUE, Up/Down, the keypad, ENTER and CANCEL keep their stock roles.

# COLUMN
## ABOUT OROVELA
Orovela is a streamlined OS for the Ensoniq Mirage that puts the focus on simplicity, ease of use, and synthesis.
No multisamples, velocity layers, or complicated interactions between similar parameters.

Sample a sound and it's mapped across the whole keyboard with immediate access to amp, filter, and pitch parameters -- now controllable live from the mod wheel.

The freed-up **SEQ, SAMPLE and LOAD** buttons take new jobs (shown above).

Orovela takes its name from the Georgian harvest song famously recorded by Hamlet Gonashvili.

### The mod wheel is the editor
1. Press **PARAM** then select the desired two-digit number (or step with Up/Down)
2. Move the **mod wheel** -- instant sweepable changes
3. Precise edits: press **VALUE** and enter the value on the keypad, or step with Up/Down

Orovela also responds to MIDI CC1 for editing control from an external keyboard (which can be switched off).

The mod wheel can also be changed to directly control LFO depth to different parameters instead of editing.

### The default sawtooth
At power-up Orovela builds a band-limited **sawtooth** in sample memory, so the Mirage is a
playable analog-filter synth before you record anything. Recording replaces it; loading an
empty slot brings it back.

# COLUMN
## SYNTH ENGINE
- **8 voices**, each through its own analog 4-pole **CEM3328 filter**. The cutoff is calibrated at boot to the brightest safe ceiling for your unit; resonance runs up to controllable self-oscillation.
- **Three envelopes**: amplitude, pitch, filter (cutoff and/or resonance)
- **LFO**
	- Waveforms: triangle, saw up/down, square, random sample-and-hold
	- Phase: triggered on keypress, free-running
	- Destinations: amp, cutoff, pitch, and resonance
- **Velocity** to loudness, cutoff and resonance; filter **keyboard tracking** either way
- **Detune layer**: a second oscillator per voice blended in - from slow unison shimmer to ±1 octave - with optional random drift
- **Looping**: loop or one-shot, forward or reverse, adjustable start and end
- **Four capture rates**, ~2 s at 15.5 kHz to ~9.6 s at 3.4 kHz, with a tunable anti-alias input filter and manual or threshold trigger
- **MIDI** on one channel: notes, velocity, pitch bend, mod wheel, sustain - in and out
- **10 program slots** on the boot disk, each holding the sample and every parameter

# COLUMN
## SAMPLING
1. **SET UP.** Source into the rear Audio In. Param 2 = 1 for line (best), 0 for mic. Pick a rate with param 1: higher is brighter but shorter.
2. **ARM: press SEQ REC.** The display shows a **level meter** in bars: one bar = quiet, two = healthy, three = hot (the top bar lights just before clipping). Aim for peaks that just flicker the top bar. The input filter (param 3) is live while armed - tune it by ear. **CANCEL** disarms.
3. **RECORD: press SEQ REC again.** Manual trigger (param 4 = 0) records immediately. Auto trigger (param 4 = 1) listens and starts on the first sound louder than the threshold (param 5, same scale as the meter); if nothing comes it gives up waiting and records anyway after ~4 s (rate 4) to ~19 s (rate 1).
4. **PLAY.** The sample sits at its original pitch on middle C (move with param 7, base note). Sampling does not change parameter values.

### Shaping the sample
Set loop start/end (17/18) for a sustain loop, or
param 13 = 0 for one-shot. Trim with sample start/end (15/16); flip with 14. Looped notes
begin at the loop start.

> Moving a start or loop point rearranges sample memory about a second after you stop moving the wheel - the display blanks briefly. That is normal.

# COLUMN
## SAVING + LOADING PROGRAMS
A **program** is the sample (or the saw) plus every parameter. An Orovela disk image can hold ten slots, **0-9**.

**SAVE**
1. Press **SEQ SAVE**. Both decimal points light (slot-pick mode).
2. Enter the slot digit **0-9**; the display shows it.
3. Press **ENTER** to write, or **CANCEL** to back out.

**LOAD**

Same process as saving, but start with **SEQ LOAD**. Loading an **empty slot** is a clean start: the default saw
and default parameters (it can take a few presses of ENTER).

> Saving overwrites the slot without further warning. Flashing a new Orovela version onto the disk blanks all ten slots - keep a copy of the disk image first. Orovela Sample Manager on a computer can import WAVs into slots and export them.

## UTILITY
- **Octave:** SAMPLE UPPER = +1 octave, SAMPLE LOWER = -1 (up to ±2). Press both together to return to normal pitch.
- **Reset synth params:** LOAD UPPER + LOAD LOWER together. Every sound parameter returns to its default; sample data does not change. Control/MIDI settings (71-75, 77) are preserved.
- **MIDI panic:** press SEQ PLAY twice within ~0.7 s. Every sounding note fades out through its release, sustain is cleared, and the keyboard and MIDI input resync.
- **Sustain:** the pedal, or MIDI CC64 on the channel set by param 71.
