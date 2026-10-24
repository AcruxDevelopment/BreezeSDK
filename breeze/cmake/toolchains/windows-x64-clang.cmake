# windows-x64-clang: Clang with its own GNU-style driver (clang++) building
# for x64 Windows, as in an MSYS2 CLANG64 shell. Not clang-cl -- see
# windows-x64-clang-cl for that.
#
# Nothing is pinned: the CLANG64 environment is what makes clang++ target
# x64 with the mingw ABI. TargetSelection.cmake checks that afterwards.
#
# See _common.cmake (pmn_msys_clang_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-x64-clang")
pmn_msys_clang_toolchain()
