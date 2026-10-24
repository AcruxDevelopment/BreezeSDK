# linux-x64-gcc: GCC building for 64-bit x86 (x86_64) Linux.
#
#   On x64 hardware: a native build with the ordinary g++.
#   Any other Linux machine: a cross build with x86_64-linux-gnu-g++.
#                 breeze/scripts/setup.sh installs this for you on apt
#                 (g++-x86-64-linux-gnu); not through dnf or pacman -- see
#                 _common.cmake's own comment (and this is a rare case in
#                 the first place: it only matters on a non-x64 Linux host).
#                 If qemu-x86_64 is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-x64-gcc")
pmn_linux_toolchain(x64 gcc)
