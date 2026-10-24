# windows-arm64-msvc: Microsoft's cl.exe building for ARM64 Windows.
#
# Run from an "ARM64 Native Tools Command Prompt for VS" (on an ARM64
# machine) or an "x64_arm64 Cross Tools Command Prompt for VS" (on an x64
# machine cross-building for ARM64). cl.exe cannot be pointed at an
# architecture from here, the developer environment decides it.
# TargetSelection.cmake verifies the cl.exe it got really targets ARM64.
#
# See _common.cmake (pmn_msvc_toolchain).
include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

pmn_toolchain_target("windows-arm64-msvc")
pmn_msvc_toolchain(arm64)
