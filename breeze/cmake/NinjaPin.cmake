# =============================================================================
# NinjaPin.cmake
#
# Pure computation of "where does the pinned ninja live, and where would it
# be downloaded from" -- no network calls, no download, no extraction.
# Mirrors DoxygenPin.cmake exactly; see that file for the full rationale.
# Shared by two very different callers:
#
#   breeze/scripts/build.sh / build.bat  include() this (via `cmake -P`, same
#                                 mechanism as FetchNinja.cmake below) to
#                                 find out where to LOOK for an
#                                 already-downloaded pinned ninja, before
#                                 CMake configure even runs -- ninja is
#                                 needed as the generator itself, unlike
#                                 Doxygen, which is only ever needed for a
#                                 downstream custom target. Never
#                                 downloads anything itself.
#
#   breeze/cmake/FetchNinja.cmake        include()s this when run standalone via
#                                 `cmake -P breeze/cmake/FetchNinja.cmake` (what
#                                 breeze/scripts/setup.sh / setup.bat call) to
#                                 know what to actually download.
#
# Needs TOOLCACHE_DIR to already be set. Both callers above set it manually
# (matching project/Configuration.cmake's default) since neither runs through
# CMakeLists.txt.
#
# Bump NINJA_PINNED_VERSION to change the pinned version project-wide --
# doing so also requires updating the SHA256 hashes below to match the
# new release's assets (a stale hash fails loud and hard, on purpose, in
# FetchNinja.cmake rather than silently accepting an unexpected file).
# GitHub publishes a sha256 digest for every release asset (the
# "digest" field of its releases API, shown on the release page too); the
# hashes below were each checked against it AND against a local download,
# rather than trusted from either alone.
# =============================================================================

include_guard(GLOBAL)

if(NOT DEFINED NINJA_PINNED_VERSION)
    set(NINJA_PINNED_VERSION "1.13.2")
endif()

set(NINJA_PIN_TAG "v${NINJA_PINNED_VERSION}")
set(NINJA_PIN_ROOT "${TOOLCACHE_DIR}/ninja-${NINJA_PINNED_VERSION}")

# This is a HOST question (what machine is actually running ninja), not a
# DIST_TARGET one -- see HostArch.cmake's header. Needed even on the
# cross DIST_TARGETs (an ARM64 Linux build from an x64 machine, an x64
# macOS build on an Apple Silicon one, ...): the machine running ninja and
# the DIST_TARGET being built need not share an architecture there, and
# this file only ever cares about the former.
include("${CMAKE_CURRENT_LIST_DIR}/HostArch.cmake")
pmn_host_arch(_pmn_ninja_host_arch)

if(CMAKE_HOST_WIN32 AND _pmn_ninja_host_arch STREQUAL "x64")
    set(NINJA_PIN_URL "https://github.com/ninja-build/ninja/releases/download/${NINJA_PIN_TAG}/ninja-win.zip")
    set(NINJA_PIN_HASH "07fc8261b42b20e71d1720b39068c2e14ffcee6396b76fb7a795fb460b78dc65")
    set(NINJA_PIN_EXECUTABLE "${NINJA_PIN_ROOT}/ninja.exe")
    set(NINJA_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_UNIX AND NOT CMAKE_HOST_APPLE AND _pmn_ninja_host_arch STREQUAL "x64")
    set(NINJA_PIN_URL "https://github.com/ninja-build/ninja/releases/download/${NINJA_PIN_TAG}/ninja-linux.zip")
    set(NINJA_PIN_HASH "5749cbc4e668273514150a80e387a957f933c6ed3f5f11e03fb30955e2bbead6")
    set(NINJA_PIN_EXECUTABLE "${NINJA_PIN_ROOT}/ninja")
    set(NINJA_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_UNIX AND NOT CMAKE_HOST_APPLE AND _pmn_ninja_host_arch STREQUAL "arm64")
    # Ninja has shipped ARM64 builds since v1.12.0 (see the comment on the
    # unsupported fallback below).
    set(NINJA_PIN_URL "https://github.com/ninja-build/ninja/releases/download/${NINJA_PIN_TAG}/ninja-linux-aarch64.zip")
    set(NINJA_PIN_HASH "fd2cacc8050a7f12a16a2e48f9e06fca5c14fc4c2bee2babb67b58be17a607fc")
    set(NINJA_PIN_EXECUTABLE "${NINJA_PIN_ROOT}/ninja")
    set(NINJA_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_WIN32 AND _pmn_ninja_host_arch STREQUAL "arm64")
    set(NINJA_PIN_URL "https://github.com/ninja-build/ninja/releases/download/${NINJA_PIN_TAG}/ninja-winarm64.zip")
    set(NINJA_PIN_HASH "e52f0bdef9dfb1003229dbd6508a508c4073fd017247002adc66e5e806cb0391")
    set(NINJA_PIN_EXECUTABLE "${NINJA_PIN_ROOT}/ninja.exe")
    set(NINJA_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_APPLE)
    # ONE asset for both Intel and Apple Silicon: ninja-mac.zip holds a
    # universal (x86_64 + arm64) Mach-O binary, so unlike Linux/Windows
    # this branch doesn't care which architecture the host is -- which also
    # sidesteps the Rosetta trap HostArch.cmake describes.
    set(NINJA_PIN_URL "https://github.com/ninja-build/ninja/releases/download/${NINJA_PIN_TAG}/ninja-mac.zip")
    set(NINJA_PIN_HASH "c99048673aa765960a99cf10c6ddb9f1fad506099ff0a0e137ad8960a88f321b")
    set(NINJA_PIN_EXECUTABLE "${NINJA_PIN_ROOT}/ninja")
    set(NINJA_PIN_PLATFORM_SUPPORTED TRUE)
else()
    # What's left: 32-bit ARM Linux, and any other exotic host. (macOS and
    # ARM64 Linux/Windows have their own branches above -- Ninja's GitHub
    # releases have shipped those binaries since v1.12.0, "ARM binaries are
    # now available for Windows and Linux, too" per that release's notes.)
    # Not a guess left blank -- there is simply no 32-bit ARM Linux asset
    # upstream at NINJA_PINNED_VERSION. This project won't put an
    # unverified SHA256 into a hash meant to catch supply-chain tampering
    # (see the file-header comment above), so to add support for another
    # host: find that asset's exact name at
    # https://github.com/ninja-build/ninja/releases/tag/${NINJA_PIN_TAG},
    # download and verify it out-of-band, and add a branch here with its
    # URL and SHA256, following the pattern above. Until then this
    # degrades the same way any other unsupported host already does:
    # FetchNinja.cmake / breeze/scripts/setup.sh give a clear error, and
    # breeze/scripts/build.sh / build.bat fall back to a system ninja with a
    # warning (see those files) -- the build itself still works, just
    # without a pinned/version-locked ninja.
    set(NINJA_PIN_URL "")
    set(NINJA_PIN_HASH "")
    set(NINJA_PIN_EXECUTABLE "")
    set(NINJA_PIN_PLATFORM_SUPPORTED FALSE)
endif()
