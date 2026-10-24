# windows-arm64-clang: Clang with its own GNU-style driver (clang++) building
# for ARM64 Windows, as in an MSYS2 CLANGARM64 shell. Not clang-cl -- see
# windows-arm64-clang-cl for that.
#
# Nothing is pinned: the CLANGARM64 environment is what makes clang++ target
# ARM64 with the mingw ABI. TargetSelection.cmake checks that afterwards.
#
# See _common.cmake (pmn_msys_clang_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-arm64-clang")
pmn_msys_clang_toolchain()
