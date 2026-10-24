# macos-arm64-clang: Clang building for Apple Silicon macOS.
#
# Apple Clang from the Xcode Command Line Tools (xcode-select --install),
# or LLVM's own Clang if you point -DCMAKE_CXX_COMPILER at it.
#
# The architecture is pinned with CMAKE_OSX_ARCHITECTURES (arm64) rather
# than left to whichever process launched the compiler, so this means
# arm64 even when cmake itself is an x86_64 build running under Rosetta 2.
# The minimum macOS is 11.0, the first release for Apple Silicon, unless
# you pass -DCMAKE_OSX_DEPLOYMENT_TARGET=... yourself.
#
# See _common.cmake (pmn_macos_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("macos-arm64-clang")
pmn_macos_toolchain(arm64)
