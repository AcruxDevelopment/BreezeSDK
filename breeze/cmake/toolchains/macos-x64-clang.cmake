# macos-x64-clang: Clang building for Intel macOS.
#
# Apple Clang from the Xcode Command Line Tools (xcode-select --install),
# or LLVM's own Clang if you point -DCMAKE_CXX_COMPILER at it.
#
# The architecture is pinned with CMAKE_OSX_ARCHITECTURES (x86_64) rather
# than left to whichever process launched the compiler, so this means x64
# on an Apple Silicon Mac too -- where the result runs through Rosetta 2.
# The minimum macOS is 11.0 unless you pass
# -DCMAKE_OSX_DEPLOYMENT_TARGET=... yourself.
#
# See _common.cmake (pmn_macos_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("macos-x64-clang")
pmn_macos_toolchain(x64)
