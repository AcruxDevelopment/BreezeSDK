# linux-arm64-gcc: GCC building for 64-bit ARM (aarch64) Linux.
#
#   On ARM64 hardware: a native build with the ordinary g++.
#   Any other Linux machine: a cross build with aarch64-linux-gnu-g++.
#                 breeze/scripts/setup.sh installs this for you on apt
#                 (g++-aarch64-linux-gnu), pacman (aarch64-linux-gnu-gcc), or,
#                 from a COPR, dnf (aarch64-linux-gnu-{binutils,gcc,glibc}).
#                 If qemu-aarch64 is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-arm64-gcc")
pmn_linux_toolchain(arm64 gcc)
