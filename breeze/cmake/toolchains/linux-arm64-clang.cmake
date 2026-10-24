# linux-arm64-clang: Clang building for 64-bit ARM (aarch64) Linux.
#
#   On ARM64 hardware: a native build with the ordinary clang++.
#   Any other Linux machine: a cross build with clang++ --target=aarch64-linux-gnu
#                 (needs Clang plus the GCC cross package for the target's
#                 libstdc++/libc, or -DCMAKE_SYSROOT=...; breeze/scripts/setup.sh
#                 installs both on apt -- clang g++-aarch64-linux-gnu --
#                 pacman -- clang aarch64-linux-gnu-gcc -- or, from a COPR,
#                 dnf -- clang aarch64-linux-gnu-{binutils,gcc,glibc}).
#                 If qemu-aarch64 is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-arm64-clang")
pmn_linux_toolchain(arm64 clang)
