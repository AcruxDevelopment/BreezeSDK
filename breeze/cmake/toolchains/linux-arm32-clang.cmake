# linux-arm32-clang: Clang building for 32-bit ARM (armhf) Linux.
#
#   On 32-bit ARM hardware: a native build with the ordinary clang++.
#   Any other Linux machine: a cross build with clang++ --target=arm-linux-gnueabihf
#                 -- or whatever triple the installed cross g++ reports for
#                 itself (-dumpmachine): ARM's own GCC, the one on Arch, says
#                 arm-none-linux-gnueabihf, and Clang only finds its libraries
#                 under that name
#                 (needs Clang plus the GCC cross package for the target's
#                 libstdc++/libc, or -DCMAKE_SYSROOT=...; breeze/scripts/setup.sh
#                 installs both on apt -- clang g++-arm-linux-gnueabihf --
#                 and, from a COPR, dnf -- see linux-arm32-gcc.cmake for
#                 details, and for why not on pacman).
#                 If qemu-arm is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-arm32-clang")
pmn_linux_toolchain(arm32 clang)
