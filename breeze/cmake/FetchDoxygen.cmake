# =============================================================================
# FetchDoxygen.cmake
#
# Downloads, verifies, and extracts the pinned Doxygen (see DoxygenPin.cmake
# for the version/URL/hash) into TOOLCACHE_DIR. Run standalone, NOT included
# by the normal CMake configure:
#
#   cmake -P breeze/cmake/FetchDoxygen.cmake
#
# This is what breeze/scripts/setup.sh / setup.bat call. It's deliberately not part
# of the main `cmake --preset <name>` configure -- see breeze/cmake/Documentation.cmake,
# which only ever LOOKS for the result of this script and never downloads
# anything itself, so a plain build never depends on Doxygen or on network
# access. Safe to re-run any time; a no-op if the pinned version is already
# present.
# =============================================================================

# TOOLCACHE_DIR normally comes from project/Configuration.cmake, which isn't
# loaded in this standalone script-mode invocation -- read it from there
# directly (it holds settings only, so including it has no side
# effects) rather than
# hardcoding a second copy of its default. If you've overridden
# TOOLCACHE_DIR via -DTOOLCACHE_DIR=... at configure time, pass the same
# value here to match: cmake -DTOOLCACHE_DIR=... -P breeze/cmake/FetchDoxygen.cmake
if(NOT DEFINED TOOLCACHE_DIR)
    get_filename_component(CMAKE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
    include("${CMAKE_SOURCE_DIR}/project/Configuration.cmake")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/DoxygenPin.cmake")

if(NOT DOXYGEN_PIN_PLATFORM_SUPPORTED)
    set(_pmn_doxygen_platform_hint "")
    if(CMAKE_HOST_WIN32)
        set(_pmn_doxygen_platform_hint
            " If this looks like an ordinary 64-bit machine, double-check this isn't "
            "a 32-bit cmake.exe running under WoW64 (installed under \"Program Files "
            "(x86)\" is a good sign it is) -- that's a common, easy way to end up here "
            "even on x64/ARM64 hardware; installing the 64-bit CMake from cmake.org "
            "fixes it.")
    endif()
    message(FATAL_ERROR "No pinned Doxygen ${DOXYGEN_PINNED_VERSION} binary is configured for this host "
                         "platform.${_pmn_doxygen_platform_hint} Install Doxygen ${DOXYGEN_PINNED_VERSION} "
                         "manually, make sure it's on PATH or pass "
                         "-DDOXYGEN_EXECUTABLE=/path/to/doxygen at project-configure time, or extend "
                         "breeze/cmake/DoxygenPin.cmake with a download URL + hash for this platform.")
endif()

if(EXISTS "${DOXYGEN_PIN_EXECUTABLE}")
    message(STATUS "Doxygen ${DOXYGEN_PINNED_VERSION} already present: ${DOXYGEN_PIN_EXECUTABLE}")
    return()
endif()

message(STATUS "Downloading pinned Doxygen ${DOXYGEN_PINNED_VERSION} (cached under ${TOOLCACHE_DIR})")
set(_pmn_doxygen_archive "${TOOLCACHE_DIR}/_doxygen_download.archive")

# No EXPECTED_HASH here on purpose: file(DOWNLOAD ... EXPECTED_HASH ...)
# raises a hard, unrecoverable CMake Error on ANY failure -- including
# plain network/connectivity failures -- which would turn a "you're
# offline" hiccup into a worse error than it needs to be. Downloading
# first and verifying the hash ourselves afterward lets us give a clearer
# message for a network failure, while still treating a genuine hash
# mismatch (see below) as fully fatal.
file(DOWNLOAD "${DOXYGEN_PIN_URL}" "${_pmn_doxygen_archive}"
    STATUS _pmn_doxygen_dl_status
    SHOW_PROGRESS
)
list(GET _pmn_doxygen_dl_status 0 _pmn_doxygen_dl_code)
if(NOT _pmn_doxygen_dl_code EQUAL 0)
    list(GET _pmn_doxygen_dl_status 1 _pmn_doxygen_dl_msg)
    file(REMOVE "${_pmn_doxygen_archive}")
    message(FATAL_ERROR "Failed to download pinned Doxygen ${DOXYGEN_PINNED_VERSION}: ${_pmn_doxygen_dl_msg}. "
                         "Check your network connection and try again -- your build doesn't need this to "
                         "succeed, only `breeze/scripts/docs.sh` / `docs.bat` does.")
endif()

# Verify integrity, deliberately as a hard failure -- a mismatch here means
# the downloaded artifact doesn't match what this project expects
# (corruption or tampering in transit, or a stale pinned hash after
# bumping DOXYGEN_PINNED_VERSION in DoxygenPin.cmake without updating the
# matching hash there): a supply-chain-relevant integrity failure, not
# something to silently continue past.
file(SHA256 "${_pmn_doxygen_archive}" _pmn_doxygen_actual_hash)
string(TOLOWER "${_pmn_doxygen_actual_hash}" _pmn_doxygen_actual_hash)
string(TOLOWER "${DOXYGEN_PIN_HASH}" _pmn_doxygen_expected_hash_lc)
if(NOT _pmn_doxygen_actual_hash STREQUAL _pmn_doxygen_expected_hash_lc)
    file(REMOVE "${_pmn_doxygen_archive}")
    message(FATAL_ERROR "Pinned Doxygen ${DOXYGEN_PINNED_VERSION} download hash mismatch -- "
                         "expected ${_pmn_doxygen_expected_hash_lc}, got ${_pmn_doxygen_actual_hash}. "
                         "This usually means DOXYGEN_PINNED_VERSION was bumped in breeze/cmake/DoxygenPin.cmake "
                         "without updating the matching hash there, or the download was corrupted or "
                         "tampered with in transit.")
endif()

file(ARCHIVE_EXTRACT INPUT "${_pmn_doxygen_archive}" DESTINATION "${DOXYGEN_PIN_ROOT}")
file(REMOVE "${_pmn_doxygen_archive}")

if(NOT CMAKE_HOST_WIN32)
    file(CHMOD "${DOXYGEN_PIN_EXECUTABLE}" PERMISSIONS
        OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE
        WORLD_READ WORLD_EXECUTE)
endif()

if(EXISTS "${DOXYGEN_PIN_EXECUTABLE}")
    message(STATUS "Doxygen ${DOXYGEN_PINNED_VERSION} ready: ${DOXYGEN_PIN_EXECUTABLE}")
else()
    message(FATAL_ERROR "Download/extract completed but the expected executable is missing: "
                         "${DOXYGEN_PIN_EXECUTABLE}")
endif()
