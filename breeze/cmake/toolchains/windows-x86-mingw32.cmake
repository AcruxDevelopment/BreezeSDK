# windows-x86-mingw32: MinGW-w64 GCC building for 32-bit Windows.
#
#   Windows host: i686-w64-mingw32-g++ from an MSYS2 MINGW32 shell (or any
#                 MinGW-w64 on PATH).
#   Linux host:   a cross build. breeze/scripts/setup.sh installs this for you on
#                 apt (g++-mingw-w64-i686), dnf (mingw32-gcc-c++) or pacman
#                 (mingw-w64-gcc, which also covers the 64-bit preset
#                 above). If wine is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_mingw_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-x86-mingw32")
pmn_mingw_toolchain(x86)
