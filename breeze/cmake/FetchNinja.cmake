# =============================================================================
# FetchNinja.cmake
#
# Downloads, verifies, and extracts the pinned ninja (see NinjaPin.cmake for
# the version/URL/hash) into TOOLCACHE_DIR. Run standalone, never included by
# the normal CMake configure -- ninja is needed as the generator itself
# (`cmake -G Ninja`), so it has to be resolved *before* configure runs, unlike
# Doxygen (see FetchDoxygen.cmake), which is only needed for a downstream
# custom target:
#
#   cmake -P breeze/cmake/FetchNinja.cmake
#
# This is what breeze/scripts/setup.sh / setup.bat call, and also what breeze/scripts/
# build.sh / build.bat call on demand if neither a pinned nor a system ninja
# is found (see the comment there). Safe to re-run any time; a no-op if the
# pinned version is already present.
# =============================================================================

# TOOLCACHE_DIR normally comes from project/Configuration.cmake, which isn't
# loaded in this standalone script-mode invocation -- read it from there
# directly (it holds settings only, so including it has no side
# effects) rather than
# hardcoding a second copy of its default. If you've overridden
# TOOLCACHE_DIR via -DTOOLCACHE_DIR=... at configure time, pass the same
# value here to match: cmake -DTOOLCACHE_DIR=... -P breeze/cmake/FetchNinja.cmake
if(NOT DEFINED TOOLCACHE_DIR)
    get_filename_component(CMAKE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
    include("${CMAKE_SOURCE_DIR}/project/Configuration.cmake")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/NinjaPin.cmake")

if(NOT NINJA_PIN_PLATFORM_SUPPORTED)
    set(_pmn_ninja_platform_hint "")
    if(CMAKE_HOST_WIN32)
        set(_pmn_ninja_platform_hint
            " If this looks like an ordinary 64-bit machine, double-check this isn't "
            "a 32-bit cmake.exe running under WoW64 (installed under \"Program Files "
            "(x86)\" is a good sign it is) -- that's a common, easy way to end up here "
            "even on x64/ARM64 hardware; installing the 64-bit CMake from cmake.org "
            "fixes it.")
    endif()
    message(FATAL_ERROR "No pinned ninja ${NINJA_PINNED_VERSION} binary is configured for this host "
                         "platform.${_pmn_ninja_platform_hint} Install ninja manually and make sure "
                         "it's on PATH, or extend breeze/cmake/NinjaPin.cmake with a download URL + hash for "
                         "this platform.")
endif()

if(EXISTS "${NINJA_PIN_EXECUTABLE}")
    message(STATUS "ninja ${NINJA_PINNED_VERSION} already present: ${NINJA_PIN_EXECUTABLE}")
    return()
endif()

message(STATUS "Downloading pinned ninja ${NINJA_PINNED_VERSION} (cached under ${TOOLCACHE_DIR})")
set(_pmn_ninja_archive "${TOOLCACHE_DIR}/_ninja_download.archive")

# No EXPECTED_HASH here on purpose -- see the identical comment in
# FetchDoxygen.cmake: file(DOWNLOAD ... EXPECTED_HASH ...) raises a hard,
# unrecoverable CMake Error on ANY failure, including plain network
# failures. Downloading first and verifying the hash ourselves afterward
# lets a network failure and a genuine integrity failure be told apart and
# handled differently (see below).
file(DOWNLOAD "${NINJA_PIN_URL}" "${_pmn_ninja_archive}"
    STATUS _pmn_ninja_dl_status
    SHOW_PROGRESS
)
list(GET _pmn_ninja_dl_status 0 _pmn_ninja_dl_code)
if(NOT _pmn_ninja_dl_code EQUAL 0)
    list(GET _pmn_ninja_dl_status 1 _pmn_ninja_dl_msg)
    file(REMOVE "${_pmn_ninja_archive}")
    message(FATAL_ERROR "Failed to download pinned ninja ${NINJA_PINNED_VERSION}: ${_pmn_ninja_dl_msg}. "
                         "Check your network connection and try again, or install ninja yourself and "
                         "make sure it's on PATH -- breeze/scripts/build.sh / build.bat will use a system ninja "
                         "if no pinned one is found.")
endif()

# Verify integrity, deliberately as a hard failure -- see the identical
# comment in FetchDoxygen.cmake: a mismatch here means corruption/tampering
# in transit, or a stale pinned hash after bumping NINJA_PINNED_VERSION in
# NinjaPin.cmake without updating the matching hash there.
file(SHA256 "${_pmn_ninja_archive}" _pmn_ninja_actual_hash)
string(TOLOWER "${_pmn_ninja_actual_hash}" _pmn_ninja_actual_hash)
string(TOLOWER "${NINJA_PIN_HASH}" _pmn_ninja_expected_hash_lc)
if(NOT _pmn_ninja_actual_hash STREQUAL _pmn_ninja_expected_hash_lc)
    file(REMOVE "${_pmn_ninja_archive}")
    message(FATAL_ERROR "Pinned ninja ${NINJA_PINNED_VERSION} download hash mismatch -- "
                         "expected ${_pmn_ninja_expected_hash_lc}, got ${_pmn_ninja_actual_hash}. "
                         "This usually means NINJA_PINNED_VERSION was bumped in breeze/cmake/NinjaPin.cmake "
                         "without updating the matching hash there, or the download was corrupted or "
                         "tampered with in transit.")
endif()

file(ARCHIVE_EXTRACT INPUT "${_pmn_ninja_archive}" DESTINATION "${NINJA_PIN_ROOT}")
file(REMOVE "${_pmn_ninja_archive}")

if(NOT CMAKE_HOST_WIN32)
    file(CHMOD "${NINJA_PIN_EXECUTABLE}" PERMISSIONS
        OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE
        WORLD_READ WORLD_EXECUTE)
endif()

if(EXISTS "${NINJA_PIN_EXECUTABLE}")
    message(STATUS "ninja ${NINJA_PINNED_VERSION} ready: ${NINJA_PIN_EXECUTABLE}")
else()
    message(FATAL_ERROR "Download/extract completed but the expected executable is missing: "
                         "${NINJA_PIN_EXECUTABLE}")
endif()
