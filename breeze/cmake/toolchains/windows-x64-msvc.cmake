# windows-x64-msvc: Microsoft's cl.exe building for x64 Windows.
#
# Run from an "x64 Native Tools Command Prompt for VS" (or any shell where
# vcvars64.bat has been run): cl.exe cannot be pointed at an architecture
# from here, the developer environment decides it. TargetSelection.cmake
# verifies the cl.exe it got really targets x64.
#
# See _common.cmake (pmn_msvc_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-x64-msvc")
pmn_msvc_toolchain(x64)
