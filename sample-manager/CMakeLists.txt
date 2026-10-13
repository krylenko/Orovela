# Orovela Sample Manager — Win32 GUI tool for Orovela disk images.
#
# Cross-compile from Linux/macOS with MinGW-w64:
#   cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
#   cmake --build build            # -> build/OrovelaSampleManager-1.0.exe
#
# Native on Windows (MSYS2 MinGW-w64 shell):
#   cmake -S . -B build -G "MinGW Makefiles"
#   cmake --build build
#
# The executable embeds an Orovela disk image for "New Disk". By default that
# is ../DSKA0000_orovela_1.5.hfe; point OROVELA_DISK at your own build of
# ../source to embed that instead. Python 3 is needed to generate the embed.
cmake_minimum_required(VERSION 3.16)
project(OrovelaSampleManager VERSION 1.0 LANGUAGES C)

find_package(Python3 3.8 REQUIRED COMPONENTS Interpreter)

set(OROVELA_DISK "${CMAKE_CURRENT_SOURCE_DIR}/../DSKA0000_orovela_1.5.hfe"
    CACHE FILEPATH "Orovela OS disk image embedded as the New Disk base")
option(OROVELA_SM_TESTS "Build the host-side test harnesses (need private hardware fixtures)" OFF)

set(BASE_DISK_C "${CMAKE_CURRENT_BINARY_DIR}/base_disk.c")
add_custom_command(
  OUTPUT  "${BASE_DISK_C}"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/make_base.py"
          "${OROVELA_DISK}" "${BASE_DISK_C}"
  DEPENDS "${OROVELA_DISK}" "${CMAKE_CURRENT_SOURCE_DIR}/make_base.py"
          "${CMAKE_CURRENT_SOURCE_DIR}/../source/mirage_hfe.py"
  COMMENT "Embedding ${OROVELA_DISK}"
  VERBATIM)

# Portable core: MFM sector codec, slot format / .oro, WAV import
add_library(oro_core STATIC src/hfe.c src/slots.c src/wavio.c)
target_include_directories(oro_core PUBLIC src)
if(NOT MSVC)
  target_compile_options(oro_core PRIVATE -O2 -Wall -Wextra)
  target_link_libraries(oro_core PUBLIC m)
endif()

add_library(oro_base STATIC "${BASE_DISK_C}")

if(WIN32)
  add_executable(OrovelaSampleManager WIN32 src/main_win.c)
  target_link_libraries(OrovelaSampleManager PRIVATE oro_core oro_base comctl32 comdlg32 winmm)
  set_target_properties(OrovelaSampleManager PROPERTIES
      OUTPUT_NAME "OrovelaSampleManager-${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}")
  if(MINGW)
    target_compile_options(OrovelaSampleManager PRIVATE -O2 -Wall -Wextra)
    target_link_options(OrovelaSampleManager PRIVATE -static)
  endif()
else()
  message(STATUS "Not targeting Windows: building the core library only "
                 "(use cmake/mingw-w64-x86_64.cmake to build the .exe)")
endif()

if(OROVELA_SM_TESTS)
  # These harnesses read hardware-returned disk images and WAV fixtures from the
  # working directory (see the comments at the top of each file); they are kept
  # as a record of how each release was verified.
  add_executable(test_core test/test_core.c)
  target_link_libraries(test_core PRIVATE oro_core)
  foreach(t test_v08 test_fix test_wav)
    add_executable(${t} test/${t}.c)
    target_link_libraries(${t} PRIVATE oro_core oro_base)
  endforeach()
endif()
