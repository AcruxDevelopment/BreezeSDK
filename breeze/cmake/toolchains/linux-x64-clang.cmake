# linux-x64-clang: Clang building for 64-bit x86 (x86_64) Linux.
#
#   On x64 hardware: a native build with the ordinary clang++.
#   Any other Linux machine: a cross build with clang++ --target=x86_64-linux-gnu
#                 (needs Clang plus the GCC cross package for the target's
#                 libstdc++/libc, or -DCMAKE_SYSROOT=...; breeze/scripts/setup.sh
#                 installs both on apt -- clang g++-x86-64-linux-gnu -- see
#                 _common.cmake's own comment for other package managers).
#                 If qemu-x86_64 is installed it is registered as the
#                 emulator, so ctest can run the result.
#
# See _common.cmake (pmn_linux_toolchain) for the details and overrides.
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("linux-x64-clang")
pmn_linux_toolchain(x64 clang)
