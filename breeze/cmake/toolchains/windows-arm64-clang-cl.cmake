# windows-arm64-clang-cl: LLVM's clang-cl (the cl.exe-compatible driver)
# building for ARM64 Windows with the MSVC ABI.
#
# The target is pinned to aarch64-pc-windows-msvc (--target=), so this means
# ARM64 regardless of the machine's own architecture (an x64 machine
# cross-compiles). The MSVC STL headers and Windows SDK libraries, including
# their ARM64 variants, still come from a Visual Studio / Build Tools install.
#
# See _common.cmake (pmn_clang_cl_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-arm64-clang-cl")
pmn_clang_cl_toolchain(arm64)
