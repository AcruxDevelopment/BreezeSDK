# linux-arm32-gcc: GCC building for 32-bit ARM (armhf) Linux.
#
#   On 32-bit ARM hardware: a native build with the ordinary g++.
#   Any other Linux machine: a cross build with arm-linux-gnueabihf-g++.
#                 breeze/scripts/setup.sh installs this for you on apt
#                 (g++-arm-linux-gnueabihf) or, from a COPR, dnf
#                 (arm-linux-gnueabihf-{binutils,gcc,glibc}); not through
#                 pacman -- on Arch it exists only in the AUR, as ARM's own
#                 prebuilt toolchain split into four packages
#                 (arm-linux-gnueabihf-{binutils,glibc-headers,glibc,gcc}-bin;
#                 x64 hosts only -- see the README, "32-bit ARM on Arch").
#                 That GCC is built for the triple arm-none-linux-gnueabihf,
#                 and finds its assembler and C library by that name, so the
#                 four have to be installed together: a source-built binutils
#                 or glibc beside it is the mix that fails (_common.cmake
#                 warns about both symptoms). If qemu-arm is installed it
#                 is registered as the emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-arm32-gcc")
pmn_linux_toolchain(arm32 gcc)
