# Orovela OS — build the flashable Mirage disk image from source.
#
#   cmake -S . -B build
#   cmake --build build                 # -> build/DSKA0000_orovela_1.5.hfe
#   cmake --build build --target verify # compare against the 1.5 release
#   cmake --build build --target docs   # regenerate the PDFs (needs reportlab + pypdf)
#
# The toolchain is pure Python 3 (assembler, HFE codec, disk builder); CMake only
# drives it. Running `python3 build_unified.py out.hfe` directly does the same thing.
cmake_minimum_required(VERSION 3.16)
project(Orovela VERSION 1.5 LANGUAGES NONE)

find_package(Python3 3.8 REQUIRED COMPONENTS Interpreter)

set(OROVELA_SRC   "${CMAKE_CURRENT_SOURCE_DIR}/os_unified.asm")
set(OROVELA_BASE  "${CMAKE_CURRENT_SOURCE_DIR}/DSKA0000_base.hfe")
set(OROVELA_IMAGE "${CMAKE_CURRENT_BINARY_DIR}/DSKA0000_orovela_${PROJECT_VERSION}.hfe")

add_custom_command(
  OUTPUT  "${OROVELA_IMAGE}"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/build_unified.py"
          --src "${OROVELA_SRC}" --base "${OROVELA_BASE}" "${OROVELA_IMAGE}"
  DEPENDS "${OROVELA_SRC}" "${OROVELA_BASE}"
          "${CMAKE_CURRENT_SOURCE_DIR}/build_unified.py"
          "${CMAKE_CURRENT_SOURCE_DIR}/assembler_fixed.py"
          "${CMAKE_CURRENT_SOURCE_DIR}/mirage_hfe.py"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Assembling os_unified.asm -> ${OROVELA_IMAGE}"
  VERBATIM)
add_custom_target(orovela ALL DEPENDS "${OROVELA_IMAGE}")

add_custom_target(verify
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/verify_build.py" "${OROVELA_IMAGE}"
  DEPENDS orovela
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  VERBATIM)

# Documentation PDFs (optional; pip install reportlab pypdf)
set(DOCS "${CMAKE_CURRENT_SOURCE_DIR}/docs")
set(SM_DOCS "${CMAKE_CURRENT_SOURCE_DIR}/../sample-manager/docs")
add_custom_target(docs
  COMMAND "${Python3_EXECUTABLE}" "${DOCS}/make_card.py"
  COMMAND "${Python3_EXECUTABLE}" "${DOCS}/make_manual.py"
          "${DOCS}/OROVELA_user_manual.md" "${CMAKE_CURRENT_BINARY_DIR}/OROVELA_user_manual.pdf"
  COMMAND "${Python3_EXECUTABLE}" "${DOCS}/make_manual.py"
          "${SM_DOCS}/SAMPLE_MANAGER_manual.md" "${CMAKE_CURRENT_BINARY_DIR}/SAMPLE_MANAGER_manual.pdf"
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  COMMENT "Generating parameter card and manuals"
  VERBATIM)
