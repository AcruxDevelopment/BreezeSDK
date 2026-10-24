# windows-x64-mingw64: MinGW-w64 GCC building for 64-bit Windows.
#
#   Windows host: x86_64-w64-mingw32-g++ from an MSYS2 MINGW64 shell (or any
#                 MinGW-w64 on PATH).
#   Linux host:   a cross build. breeze/scripts/setup.sh installs this for you on
#                 apt (g++-mingw-w64-x86-64), dnf (mingw64-gcc-c++) or
#                 pacman (mingw-w64-gcc, which also covers the 32-bit
#                 preset below). If wine is installed it is registered as
#                 the emulator, so ctest can run the result.
#
# See _common.cmake (pmn_mingw_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-x64-mingw64")
pmn_mingw_toolchain(x64)
