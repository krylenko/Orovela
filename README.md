# Orovela

**A new operating system for the Ensoniq Mirage DSK-8 sampler**, plus a
Windows sample manager for Orovela disks.

Orovela is a from-scratch 6809 OS that replaces the stock Mirage firmware
with a streamlined, synthesis-first instrument. Sample a sound and it's mapped
across the whole keyboard, with immediate access to amp, filter and pitch
parameters, all editable live from the mod wheel. There are no multisamples,
velocity layers or overlapping parameter systems.

- 8 voices, each through its own analog CEM3328 4-pole filter, with the cutoff
  calibrated at boot and resonance up to controlled self-oscillation
- Three envelopes (amp, pitch, filter) and an LFO with five waveforms, two
  speed ranges and four destinations
- Four sample rates, from 3.4 kHz (9.6 s) to 15.5 kHz (2.1 s), with clean
  loops at any start and end point
- Ten program slots per disk (32 KB sample plus all parameters)
- MIDI in, with CC1 driving the mod-wheel editor (works for rackmount units)
- A band-limited sawtooth built at power-up, so the Mirage plays as an analog
  synth before you record anything

Orovela takes its name from the Georgian harvest song famously recorded by
Hamlet Gonashvili.

## What's here

| File / folder | What it is |
|---|---|
| `DSKA0000_orovela_1.5.hfe` | Orovela 1.5 boot disk, ready to load on a Gotek/HxC floppy emulator |
| `OrovelaSampleManager-1.0.exe` | Sample manager for Windows: no install, no dependencies |
| `Orovela 1.5 User Manual.pdf` | One-page guide to playing and editing |
| `Orovela 1.5 Parameter Card.pdf` | Every parameter with its range and default |
| `Orovela Sample Manager 1.0 Manual.pdf` | Guide to the sample manager |
| `source/` | OS source, assembler, disk tools and build scripts |
| `sample-manager/` | Sample manager source and build scripts |

## Getting started

1. Copy `DSKA0000_orovela_1.5.hfe` to the USB stick of a floppy emulator
   (FlashFloppy/Gotek or HxC) attached to the Mirage, or write it to a real
   3.5" DD disk.
2. Boot the Mirage from it as you would the stock OS disk.
3. Keep the parameter card next to the instrument.

Programs are saved to the same disk. **Writing a new OS image erases all ten
slots**, so export your programs as `.oro` files with the sample manager before
updating to a new build.

The sample manager opens Orovela disk images and lets you audition, extract
(WAV) and import (WAV or `.oro`) programs, and create fresh disks with
Orovela 1.5 pre-installed.

## Building from source

Both projects use CMake. The OS toolchain is pure Python 3, with no external
assembler needed.

    # OS disk image (byte-identical to the release)
    cmake -S source -B build/os
    cmake --build build/os
    cmake --build build/os --target verify

    # Sample manager (MinGW-w64 cross-compile)
    cmake -S sample-manager -B build/sm \
          -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
    cmake --build build/sm

See `source/README.md` and `sample-manager/BUILD.md` for details.

## License

MIT; see `LICENSE`.
