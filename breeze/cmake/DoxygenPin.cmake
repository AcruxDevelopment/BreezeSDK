# =============================================================================
# DoxygenPin.cmake
#
# Pure computation of "where does the pinned Doxygen live, and where would
# it be downloaded from" -- no network calls, no download, no extraction.
# Shared by two very different callers, which is why this is its own file:
#
#   breeze/cmake/Documentation.cmake  include()s this during the normal CMake
#                              configure to find out where to LOOK for an
#                              already-downloaded pinned Doxygen. Never
#                              downloads anything itself -- see that file.
#
#   breeze/cmake/FetchDoxygen.cmake   include()s this when run standalone via
#                              `cmake -P breeze/cmake/FetchDoxygen.cmake` (what
#                              breeze/scripts/setup.sh / setup.bat call) to know
#                              what to actually download.
#
# Needs TOOLCACHE_DIR to already be set -- Documentation.cmake gets it from
# project/Configuration.cmake (included earlier by CMakeLists.txt); FetchDoxygen.cmake
# sets it manually since script mode (`cmake -P`) never runs CMakeLists.txt.
#
# Bump DOXYGEN_PINNED_VERSION to change the pinned version project-wide --
# doing so also requires updating the SHA256 hashes below to match the
# new release's assets (each was checked against the digest GitHub
# publishes for the asset AND a local download, not trusted from either
# alone). A stale hash fails loud and hard, on purpose, in
# FetchDoxygen.cmake rather than silently accepting an unexpected file).
# =============================================================================

include_guard(GLOBAL)

if(NOT DEFINED DOXYGEN_PINNED_VERSION)
    set(DOXYGEN_PINNED_VERSION "1.16.1")
endif()

string(REPLACE "." "_" _pmn_doxygen_tag_version "${DOXYGEN_PINNED_VERSION}")
set(DOXYGEN_PIN_TAG "Release_${_pmn_doxygen_tag_version}")
set(DOXYGEN_PIN_ROOT "${TOOLCACHE_DIR}/doxygen-${DOXYGEN_PINNED_VERSION}")

# This is a HOST question (what machine is actually running Doxygen), not
# a DIST_TARGET one -- see HostArch.cmake's header. Needed even on the
# cross DIST_TARGETs (an ARM64 Linux build from an x64 machine, an x64
# macOS build on an Apple Silicon one, ...): the machine running Doxygen and
# the DIST_TARGET being built need not share an architecture there, and
# this file only ever cares about the former.
include("${CMAKE_CURRENT_LIST_DIR}/HostArch.cmake")
pmn_host_arch(_pmn_doxygen_host_arch)

if(CMAKE_HOST_WIN32 AND _pmn_doxygen_host_arch STREQUAL "x64")
    set(DOXYGEN_PIN_URL "https://github.com/doxygen/doxygen/releases/download/${DOXYGEN_PIN_TAG}/doxygen-${DOXYGEN_PINNED_VERSION}.windows.x64.bin.zip")
    set(DOXYGEN_PIN_HASH "ddfa59a4ae9549651330471c2e387ec7a9891080543faed541c859e5ce448653")
    set(DOXYGEN_PIN_EXECUTABLE "${DOXYGEN_PIN_ROOT}/doxygen.exe")
    set(DOXYGEN_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_UNIX AND NOT CMAKE_HOST_APPLE AND _pmn_doxygen_host_arch STREQUAL "x64")
    set(DOXYGEN_PIN_URL "https://github.com/doxygen/doxygen/releases/download/${DOXYGEN_PIN_TAG}/doxygen-${DOXYGEN_PINNED_VERSION}.linux.bin.tar.gz")
    set(DOXYGEN_PIN_HASH "a56f885d37e3aae08a99f638d17bbb381224c03a878d9e2dda4f9fa4baf1d8bd")
    set(DOXYGEN_PIN_EXECUTABLE "${DOXYGEN_PIN_ROOT}/doxygen-${DOXYGEN_PINNED_VERSION}/bin/doxygen")
    set(DOXYGEN_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_APPLE AND _pmn_doxygen_host_arch STREQUAL "arm64")
    # macOS ships two plain zips (next to the .dmg GUI installers, which are
    # deliberately not used here: mounting a disk image needs hdiutil and a
    # GUI app bundle around what is, inside, just this CLI binary). Each
    # holds doxygen-<version>/doxygen -- no bin/ level, unlike the Linux
    # tarball. Which one is the MACHINE's architecture, not the cmake
    # process's, courtesy of HostArch.cmake's Rosetta handling.
    set(DOXYGEN_PIN_URL "https://github.com/doxygen/doxygen/releases/download/${DOXYGEN_PIN_TAG}/doxygen-${DOXYGEN_PINNED_VERSION}-mac-arm.zip")
    set(DOXYGEN_PIN_HASH "f75d4e7253ad959d691cb65b6c3a9bb0c138ce75bce7cef17f5ebf36c7b54bdc")
    set(DOXYGEN_PIN_EXECUTABLE "${DOXYGEN_PIN_ROOT}/doxygen-${DOXYGEN_PINNED_VERSION}/doxygen")
    set(DOXYGEN_PIN_PLATFORM_SUPPORTED TRUE)
elseif(CMAKE_HOST_APPLE AND _pmn_doxygen_host_arch STREQUAL "x64")
    set(DOXYGEN_PIN_URL "https://github.com/doxygen/doxygen/releases/download/${DOXYGEN_PIN_TAG}/doxygen-${DOXYGEN_PINNED_VERSION}-mac-intel.zip")
    set(DOXYGEN_PIN_HASH "1530e5eca05b442e4cdd80a8ad6b22e1bbb3fc14e12b64b07c61de4be48cc5f1")
    set(DOXYGEN_PIN_EXECUTABLE "${DOXYGEN_PIN_ROOT}/doxygen-${DOXYGEN_PINNED_VERSION}/doxygen")
    set(DOXYGEN_PIN_PLATFORM_SUPPORTED TRUE)
else()
    # What's left: Windows or Linux on ARM64/ARM32, and any other exotic
    # host. (macOS has its own branches above.) Unlike Ninja (see the
    # equivalent comment in NinjaPin.cmake), the upstream Doxygen
    # project's GitHub releases don't publish ARM Linux or ARM Windows
    # binaries at all as of DOXYGEN_PINNED_VERSION -- the release's asset
    # list is the two macOS zips, two macOS disk images, the x64 Linux
    # tarball, the x64 Windows zip and installer, the sources, and the
    # manual -- so this isn't fillable yet.
    # To add support once/if such an asset exists: find its exact name at
    # https://github.com/doxygen/doxygen/releases/tag/${DOXYGEN_PIN_TAG},
    # download and verify it out-of-band, and add a branch here with its
    # URL and SHA256, following the pattern above; this project won't put
    # an unverified hash into one meant to catch supply-chain tampering
    # (see the file-header comment above). Until then this degrades the
    # same way any other unsupported host already does: FetchDoxygen.cmake
    # gives a clear error, and Documentation.cmake disables ENABLE_DOXYGEN
    # with a warning instead of failing the build (see that file) -- a
    # plain build never depends on Doxygen regardless.
    set(DOXYGEN_PIN_URL "")
    set(DOXYGEN_PIN_HASH "")
    set(DOXYGEN_PIN_EXECUTABLE "")
    set(DOXYGEN_PIN_PLATFORM_SUPPORTED FALSE)
endif()
