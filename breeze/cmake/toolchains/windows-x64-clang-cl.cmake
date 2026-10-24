# windows-x64-clang-cl: LLVM's clang-cl (the cl.exe-compatible driver)
# building for x64 Windows with the MSVC ABI.
#
# The target is pinned to x86_64-pc-windows-msvc (--target=), so this means
# x64 regardless of the machine's own architecture. The MSVC STL headers and
# Windows SDK libraries still come from a Visual Studio / Build Tools install.
#
# See _common.cmake (pmn_clang_cl_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-x64-clang-cl")
pmn_clang_cl_toolchain(x64)
