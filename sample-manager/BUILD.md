# Building the Orovela Sample Manager

A single-window Win32 program in portable C (C99) with no dependencies beyond
the Windows SDK libraries `comctl32`, `comdlg32` and `winmm`. It is built with
MinGW-w64 — either cross-compiled from Linux/macOS or natively under MSYS2.

## Requirements

- CMake 3.16+
- MinGW-w64 GCC (`apt install gcc-mingw-w64-x86-64`, `brew install mingw-w64`,
  or the MSYS2 `mingw-w64-x86_64-gcc` package)
- Python 3.8+ (generates the embedded disk image; uses `../source/mirage_hfe.py`)

## Build

Cross-compile:

    cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
    cmake --build build
    # -> build/OrovelaSampleManager-1.0.exe

Native, from an MSYS2 MinGW64 shell:

    cmake -S . -B build -G "MinGW Makefiles"
    cmake --build build

MSVC has not been tested.

## The embedded OS image

"New Disk" creates a disk from an Orovela image compiled into the program.
The build generates `base_disk.c` from `../DSKA0000_orovela_1.5.hfe`, with all
ten slot headers blanked. To embed your own OS build instead:

    cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake \
          -DOROVELA_DISK=/path/to/your_build.hfe

Or run the generator by hand: `python3 make_base.py <orovela.hfe> base_disk.c`.

## Without CMake

    python3 make_base.py ../DSKA0000_orovela_1.5.hfe base_disk.c
    x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -mwindows -static -Isrc \
        -o OrovelaSampleManager-1.0.exe \
        src/main_win.c src/hfe.c src/slots.c src/wavio.c base_disk.c \
        -lcomctl32 -lcomdlg32 -lwinmm

## Tests

`-DOROVELA_SM_TESTS=ON` (with a native host compiler, no toolchain file) builds
the host-side harnesses in `test/`. They were used to verify each release
against disks returned from real hardware and the Python reference codec.
Those fixture images and WAVs are not part of this repository, so the
harnesses report missing files unless you supply your own. The comments at the
top of each file list what it expects.

## Layout

    src/hfe.h, src/hfe.c        MFM sector codec (C port of ../source/mirage_hfe.py)
    src/slots.h, src/slots.c    slot format, .oro, WAV export, Orovela validation
    src/wavio.h, src/wavio.c    WAV import: parse, resample, quantize, header build
    src/param_defaults.h        PARMTAB defaults (from ../source/new_params.json)
    src/main_win.c              Win32 GUI (ANSI, single window)
    make_base.py                generates base_disk.c from an Orovela .hfe
    cmake/                      MinGW-w64 cross toolchain file
    test/                       host-side verification harnesses
    docs/                       manual source (render with ../source/docs/make_manual.py)

The slot layout is documented in `../source/docs/TOOLCHAIN_AND_DISK_FORMAT.md`;
the `.oro` container format is in `README.md` and `src/slots.h`.
