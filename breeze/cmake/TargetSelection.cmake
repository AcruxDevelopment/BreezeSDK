# =============================================================================
# TargetSelection.cmake
#
# What the build is FOR: DIST_TARGET -- a single "<platform>-<arch>-<compiler>"
# string -- and the PLATFORM, ARCHITECTURE and COMPILER_ID derived from it.
# Included by breeze/cmake/Breeze.cmake right after project(), since it needs
# real compiler detection; the project's own settings (project/Configuration.cmake)
# deliberately have none of it, so that a plain `cmake -P` script can read them.
#
# Everything below is the template's: nothing in it is configuration. To build
# for a different target, pick a CMakePresets.json preset or pass -DDIST_TARGET.
#
# -----------------------------------------------------------------------
# Target selection (DIST_TARGET)
# -----------------------------------------------------------------------
# DIST_TARGET identifies what you're building for as a single
# "<platform>-<arch>-<compiler>" string. It is declared by the toolchain
# file in use (breeze/cmake/toolchains/<DIST_TARGET>.cmake -- what every
# CMakePresets.json preset selects, and the recommended way to build), or
# given explicitly with -DDIST_TARGET=<value> (if both are present they
# must agree), or, with neither, auto-detected from the compiler CMake
# found. Every value in PMN_VALID_DIST_TARGETS below is supported:
#
#   linux-x64-gcc          GCC on x86-64 Linux
#   linux-x64-clang        Clang on x86-64 Linux
#   linux-arm64-gcc        GCC on 64-bit ARM Linux (aarch64)
#   linux-arm64-clang      Clang on 64-bit ARM Linux (aarch64)
#   linux-arm32-gcc        GCC on 32-bit ARM Linux (armhf/armv7l and similar)
#   linux-arm32-clang      Clang on 32-bit ARM Linux
#   macos-arm64-clang      Clang on Apple Silicon macOS -- Apple Clang from
#                          the Xcode Command Line Tools, or LLVM's own
#                          Clang (e.g. Homebrew's); both are "clang" here
#   macos-x64-clang        Clang on Intel macOS (or, given Rosetta 2, an
#                          Apple Silicon Mac: the toolchain just asks the
#                          compiler for -arch x86_64)
#   windows-x64-msvc       cl.exe (MSVC) targeting x64
#   windows-arm64-msvc     cl.exe (MSVC) targeting ARM64
#   windows-x64-clang-cl   clang-cl targeting x64 (Clang targeting the
#                          MSVC ABI -- CMake's MSVC variable is TRUE for
#                          this too)
#   windows-arm64-clang-cl clang-cl targeting ARM64
#   windows-x64-clang      Clang with its own GNU-style driver on Windows,
#                          targeting x64 (e.g. an MSYS2 CLANG64
#                          environment) -- distinct from clang-cl above,
#                          which mimics cl.exe instead of gcc
#   windows-arm64-clang    Clang with its own GNU-style driver on Windows,
#                          targeting ARM64 (e.g. an MSYS2 CLANGARM64
#                          environment)
#   windows-x86-mingw32    32-bit x86 GCC via MinGW
#   windows-x64-mingw64    64-bit x64 GCC via MinGW-w64
#
# No macOS GCC target and no universal one. Apple's own toolchain IS Clang
# (a Homebrew GCC would be a second, unrelated compiler ecosystem needing
# its own SDK and sysroot handling), and a universal binary is a
# CMAKE_OSX_ARCHITECTURES list with two entries -- which doesn't fit a
# DIST_TARGET that names ONE architecture, and is rejected below with the
# reason rather than mislabeled. To ship one universal file, build both
# macOS presets and combine the results: `lipo -create <arm64 file>
# <x64 file> -output <file>`.
#
# No windows-arm32-* and no ARM64 MinGW target: 32-bit ARM Windows has no
# real toolchain support left in any of the compilers above (MSVC dropped
# it; it only ever existed for Windows RT / Windows 10 IoT Core), and
# mainline MinGW-w64's GCC has no ARM64 Windows (PE/COFF) backend -- ARM64
# Windows toolchains in that ecosystem are LLVM-based (MSYS2's
# CLANGARM64, covered by windows-arm64-clang above), not GCC-based.
#
# Architecture (x64/arm64/arm32) is detected differently depending on
# compiler family, because CMAKE_SYSTEM_PROCESSOR turns out not to be
# trustworthy for all of them:
#   - Linux (GCC/Clang) goes through breeze/cmake/HostArch.cmake's
#     pmn_target_arch(), i.e. CMAKE_SYSTEM_PROCESSOR: `uname -m` for a
#     native build, and whatever the toolchain file sets it to for a
#     cross build (so an aarch64 cross build from an x64 machine is
#     labeled arm64, not x64). Clang's GNU-style driver on Windows goes
#     through pmn_host_arch() instead, an environment-variable check --
#     see that file for why CMAKE_SYSTEM_PROCESSOR/
#     CMAKE_HOST_SYSTEM_PROCESSOR can't be trusted there (a second,
#     related trap: a 32-bit cmake.exe under WoW64, independent of the
#     MSVC one below).
#   - macOS goes through CMAKE_OSX_ARCHITECTURES, which the macOS toolchain
#     files set to exactly one architecture, and only falls back to
#     CMAKE_SYSTEM_PROCESSOR (`uname -m`) without one. Apple's clang is a
#     single multi-architecture compiler, so an x86_64 build on an Apple
#     Silicon Mac is just a different -arch -- not a cross compiler, and
#     nothing that CMAKE_SYSTEM_PROCESSOR (which under Rosetta 2 reports
#     the architecture of the cmake PROCESS, the same class of trap as
#     WoW64 on Windows) could describe reliably.
#   - MSVC and clang-cl use CMAKE_CXX_COMPILER_ARCHITECTURE_ID instead --
#     CMAKE_SYSTEM_PROCESSOR is a documented, confirmed-in-the-wild trap
#     here (tracked as CMake issue #25466): it reflects the architecture
#     of the cmake.exe process itself, not what the selected cl.exe/
#     clang-cl actually targets, and those two routinely differ (a
#     same-machine cross build -- e.g. an x64 Visual Studio install's
#     "HostX64/ARM64" tools -- is the normal way to target ARM64 from an
#     x64 dev machine).
#
# Toolchain files and cross-compiling: breeze/cmake/toolchains/ has one toolchain
# file per DIST_TARGET, named after it, and every CMakePresets.json preset
# selects the one named after itself. A toolchain file settles the compiler
# (and, for clang-cl, the --target triple) before project() runs, declares
# the DIST_TARGET it is for, and -- where the target isn't the machine
# running CMake -- sets up a real cross build: the linux-arm64-* and
# linux-arm32-* targets cross-compile from any other Linux machine (an x64
# one, say), and the windows-*-mingw* targets from Linux via mingw-w64,
# while on matching hardware (ARM64 for linux-arm64-*) the very same
# preset just builds natively. On macOS the toolchain pins the
# architecture with CMAKE_OSX_ARCHITECTURES and a minimum macOS version
# with CMAKE_OSX_DEPLOYMENT_TARGET (11.0 unless you pass your own) -- both
# are only honored when set BEFORE project(), which is exactly when a
# toolchain file runs. breeze/cmake/toolchains/_common.cmake documents
# exactly what each one does and which packages it needs. The exception is
# MSVC: cl.exe takes its architecture from the Visual Studio developer
# environment it is started from (vcvarsall.bat), which no CMake file can
# switch, so the windows-*-msvc toolchains only pick cl and check it is
# there -- the architecture check below then verifies it is the right one.
#
# Without a toolchain file, pointing -DCMAKE_CXX_COMPILER at a cross
# compiler is not enough on its own: CMake is never told the target is a
# different architecture, so the auto-detected DIST_TARGET follows the
# HOST and you'll get a cross-check mismatch (see below) instead, same as
# any other unmet assumption this file's auto-detection makes.
#
# IMPORTANT: -DDIST_TARGET=... on its own only labels the build (which
# install subdirectory it lands in, which metadata gets printed); it does
# NOT select a compiler or an architecture. CMake still uses whatever
# CMAKE_CXX_COMPILER it would otherwise find -- your PATH, your
# environment, or an explicit -DCMAKE_CXX_COMPILER=... -- same as if
# DIST_TARGET had never been mentioned. Passing
# -DDIST_TARGET=windows-x64-mingw64 alone, with no MinGW compiler actually
# configured, does not make CMake go find one; it configures whatever
# compiler it would have anyway (often MSVC, since CMake looks for that
# first on Windows) and mislabels the result. TargetSelection.cmake catches
# exactly this: a DIST_TARGET that disagrees with what the real compiler
# (and architecture) auto-detects to is a FATAL_ERROR, not a silent
# mislabel -- see the "cross-check" step below. A toolchain file doesn't
# have the problem, because it sets the label and the compiler together:
# use the toolchain file for that target
# (-DCMAKE_TOOLCHAIN_FILE=breeze/cmake/toolchains/<DIST_TARGET>.cmake), or simply
# the matching CMakePresets.json preset, which selects it.
#
# Auto-detection FATAL_ERRORs rather than guessing when the compiler
# doesn't match any of the above, instead of silently assuming MSVC --
# that silent assumption is exactly what used to misidentify a MinGW GCC
# build as MSVC (COMPILER_ID "msvc" for an actual GNU compiler), which in
# turn misfiled its `cmake --install` output under .../windows-x64-msvc/.
#
# PLATFORM, ARCHITECTURE, and COMPILER_ID below are metadata derived from
# DIST_TARGET; Breeze.cmake and the other breeze/cmake/*.cmake modules consume these
# rather than re-deriving them.
# =============================================================================

include_guard(GLOBAL)

set(PMN_VALID_DIST_TARGETS
    linux-x64-gcc
    linux-x64-clang
    linux-arm64-gcc
    linux-arm64-clang
    linux-arm32-gcc
    linux-arm32-clang
    macos-arm64-clang
    macos-x64-clang
    windows-x64-msvc
    windows-arm64-msvc
    windows-x64-clang-cl
    windows-arm64-clang-cl
    windows-x64-clang
    windows-arm64-clang
    windows-x86-mingw32
    windows-x64-mingw64
)
list(JOIN PMN_VALID_DIST_TARGETS "  " _pmn_valid_dist_targets_str)

# Where DIST_TARGET came from, for the messages below. A toolchain file
# (breeze/cmake/toolchains/<DIST_TARGET>.cmake -- every CMakePresets.json preset
# selects the one named after itself) declares the target it is for via
# PMN_TOOLCHAIN_DIST_TARGET (see toolchains/_common.cmake), so the label
# and the compiler the toolchain picked travel together. It is resolved
# here, ahead of the auto-detection below, because
# _pmn_dist_target_undetected() decides how hard to fail based on
# whether DIST_TARGET is already known. An explicit -DDIST_TARGET is
# still accepted alongside a toolchain, but it has to agree with it.
set(_pmn_dist_target_source "")
if(PMN_TOOLCHAIN_DIST_TARGET)
    if(DIST_TARGET AND NOT DIST_TARGET STREQUAL PMN_TOOLCHAIN_DIST_TARGET)
        message(FATAL_ERROR
            "DIST_TARGET was explicitly set to '${DIST_TARGET}', but the toolchain file in use "
            "(${CMAKE_TOOLCHAIN_FILE}) is for '${PMN_TOOLCHAIN_DIST_TARGET}'.\n"
            "Drop -DDIST_TARGET (the toolchain already says which target this is), or "
            "use the toolchain file for '${DIST_TARGET}':\n"
            "  ${CMAKE_SOURCE_DIR}/breeze/cmake/toolchains/${DIST_TARGET}.cmake")
    endif()
    set(DIST_TARGET "${PMN_TOOLCHAIN_DIST_TARGET}")
    set(_pmn_dist_target_source "toolchain")
elseif(DIST_TARGET)
    set(_pmn_dist_target_source "explicit")
endif()

# _pmn_dist_target_undetected(REASON...): an auto-detection branch
# below hit a case with no DIST_TARGET for it. REASON explains why --
# shown whether or not DIST_TARGET was explicitly given (e.g. via a
# CMakePresets.json preset), so a preset user gets the same specific
# diagnosis a plain, no-DIST_TARGET user already did.
#
# Previously REASON was only ever shown when DIST_TARGET was unset;
# setting DIST_TARGET (which every preset does -- the recommended way
# to build, per CMakePresets.json and the README) silently discarded
# it in favor of the generic "auto-detects to none of the values this
# project recognizes" cross-check message further down, with no
# explanation of WHY -- exactly the confusing, unhelpful failure this
# macro exists to prevent.
#
# No DIST_TARGET means there's nothing to fall back on, so REASON is
# the final word: FATAL_ERROR, with the full valid-values list. With
# DIST_TARGET set, REASON is advisory context for the unified
# cross-check FATAL_ERROR further down (which still runs, and has the
# copy-pasteable fix) -- so this is STATUS, and _pmn_detected_dist_target
# is left at "" for that check to pick up, same as before this macro
# existed.
macro(_pmn_dist_target_undetected)
    if(DIST_TARGET)
        set(_pmn_detected_dist_target "")
        message(STATUS "Could not auto-detect a DIST_TARGET: " ${ARGN})
    else()
        message(FATAL_ERROR "Could not auto-detect a DIST_TARGET: " ${ARGN}
            "\nValid values: ${_pmn_valid_dist_targets_str}")
    endif()
endmacro()

include("${CMAKE_CURRENT_LIST_DIR}/HostArch.cmake")

# What DIST_TARGET the CXX compiler CMake actually found auto-detects
# to -- computed unconditionally, not only when DIST_TARGET is unset,
# so an explicitly-given DIST_TARGET can be cross-checked against it
# below rather than trusted as a label. See the file header for why
# that check exists.
if(WIN32)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC" OR
       (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC"))
        # MSVC, and clang-cl (Clang's cl.exe-compatible driver
        # personality, selected either by invoking a binary literally
        # named clang-cl(.exe) or via `clang++ --driver-mode=cl`;
        # CMake surfaces this as CMAKE_CXX_COMPILER_FRONTEND_VARIANT
        # rather than a distinct COMPILER_ID, since it's the same
        # Clang either way -- just a different argument dialect and
        # default target ABI). Both get their architecture from
        # CMAKE_CXX_COMPILER_ARCHITECTURE_ID, deliberately NOT from
        # CMAKE_SYSTEM_PROCESSOR/CMAKE_HOST_SYSTEM_PROCESSOR (see
        # HostArch.cmake's header for why those can't be trusted for
        # this specific case). CMAKE_CXX_COMPILER_ARCHITECTURE_ID is
        # what CMake itself derives by probing the compiler -- it
        # needs this internally for the right /machine: linker flag --
        # so it reflects the real target regardless of which cl.exe/
        # clang-cl variant ended up on PATH. Its values are
        # mixed-case by long-standing CMake convention (X86, x64,
        # ARM, ARM64); normalized to uppercase here so the
        # comparisons below aren't tripped by that inconsistency.
        string(TOUPPER "${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}" _pmn_msvc_arch_id)
        if(_pmn_msvc_arch_id STREQUAL "X64")
            set(_pmn_win_arch "x64")
        elseif(_pmn_msvc_arch_id STREQUAL "ARM64")
            set(_pmn_win_arch "arm64")
        else()
            # Includes X86 and ARM (32-bit) -- real MSVC targets, but
            # not ones this project has a DIST_TARGET for (32-bit ARM
            # Windows has no real toolchain support left in any
            # compiler; see the file header). Treated as unrecognized
            # rather than silently mislabeled as x64 or arm64.
            set(_pmn_win_arch "")
        endif()

        if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
            set(_pmn_win_compiler_id "msvc")
        else()
            set(_pmn_win_compiler_id "clang-cl")
        endif()

        if(_pmn_win_arch)
            set(_pmn_detected_dist_target "windows-${_pmn_win_arch}-${_pmn_win_compiler_id}")
        else()
            # X86 specifically gets its own hint rather than the
            # generic message below: it's by far the most likely way
            # to actually hit this branch in practice (ARM on Windows
            # without ARM64 is rare) -- not a machine that's genuinely
            # 32-bit-only (vanishingly rare today), almost always
            # PATH/environment handing CMake the 32-bit-hosted,
            # 32-bit-targeting cl.exe/clang-cl instead of the x64 one,
            # e.g. from opening a plain shell instead of an "x64
            # Native Tools Command Prompt for VS". Reported whether or
            # not DIST_TARGET was explicitly given -- see
            # _pmn_dist_target_undetected above.
            if(_pmn_msvc_arch_id STREQUAL "X86")
                _pmn_dist_target_undetected(
                    "${_pmn_win_compiler_id} is "
                    "targeting X86 (32-bit) -- almost always a sign that PATH/the "
                    "current shell is handing CMake the 32-bit-hosted, "
                    "32-bit-targeting ${_pmn_win_compiler_id}, not that this machine "
                    "is actually 32-bit-only.\n"
                    "Open an \"x64 Native Tools Command Prompt for VS\" (or a "
                    "\"Developer PowerShell for VS\" defaulted to x64) so an x64 "
                    "${_pmn_win_compiler_id} is what's first on PATH, delete this "
                    "build directory (a failed configure's CMakeCache.txt won't just "
                    "fix itself), and reconfigure. breeze\\scripts\\build.bat enters the right environment on "
                    "its own, but the build directory still has to go.\n"
                    "If 32-bit really is intentional, this project doesn't have a "
                    "DIST_TARGET for it -- set one explicitly: -DDIST_TARGET=<value>"
                )
            else()
                _pmn_dist_target_undetected(
                    "${_pmn_win_compiler_id} is "
                    "targeting an architecture ('${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}') "
                    "this project doesn't have a DIST_TARGET for -- set one "
                    "explicitly: -DDIST_TARGET=<value>"
                )
            endif()
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        # Clang with its own GNU-style driver on Windows (e.g. an
        # MSYS2 CLANG64/CLANGARM64 environment) -- distinct from
        # clang-cl above, which mimics cl.exe instead of gcc.
        # CMAKE_CXX_COMPILER_ARCHITECTURE_ID is specific to the MSVC-
        # style detection used above and isn't populated for this
        # driver mode. Falls back to HostArch.cmake instead -- unlike
        # the raw cl.exe/clang-cl case, a GNU-style environment like
        # MSYS2 is used as a coherent whole (its own cmake, its own
        # clang++, both built for and normally run on the same
        # architecture), the same assumption the MinGW pointer-size
        # check below already makes for mingw32 vs. mingw64.
        pmn_host_arch(_pmn_win_clang_arch _pmn_win_clang_raw)
        if(_pmn_win_clang_arch STREQUAL "arm64")
            set(_pmn_detected_dist_target "windows-arm64-clang")
        elseif(_pmn_win_clang_arch STREQUAL "x64")
            set(_pmn_detected_dist_target "windows-x64-clang")
        else()
            _pmn_dist_target_undetected(
                "unrecognized host "
                "architecture '${_pmn_win_clang_raw}' for Clang's GNU-style driver "
                "on Windows -- set one explicitly: -DDIST_TARGET=<value>"
            )
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        # A real GCC on Windows is MinGW (mingw.org's original,
        # 32-bit-only project) or MinGW-w64 (adds 64-bit; also
        # provides a 32-bit target, conventionally called
        # "mingw32" too since it's the direct successor). Tell
        # them apart by pointer size rather than parsing the
        # compiler's own executable name, which is a config
        # choice, not something to depend on. No ARM MinGW target
        # here on purpose, unlike the Clang branch above: mainline
        # MinGW-w64's GCC has no ARM64 Windows (PE/COFF) backend --
        # ARM64 Windows toolchains in that ecosystem are LLVM-based
        # (MSYS2's CLANGARM64), not GCC-based.
        if(CMAKE_SIZEOF_VOID_P EQUAL 8)
            set(_pmn_detected_dist_target "windows-x64-mingw64")
        else()
            set(_pmn_detected_dist_target "windows-x86-mingw32")
        endif()
    elseif(DIST_TARGET)
        # Can't cross-check an explicit value against a compiler this
        # doesn't recognize at all -- the mismatch message below
        # handles an empty detected value.
        set(_pmn_detected_dist_target "")
    else()
        message(FATAL_ERROR
            "Could not auto-detect a DIST_TARGET for CXX compiler "
            "'${CMAKE_CXX_COMPILER_ID}' on Windows -- set one "
            "explicitly: -DDIST_TARGET=<value>\n"
            "Valid values: ${_pmn_valid_dist_targets_str}")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # macOS (CMAKE_SYSTEM_NAME is "Darwin" for macOS only; iOS and
    # friends have their own names). The architecture is what
    # CMAKE_OSX_ARCHITECTURES says when it's set -- the macOS toolchain
    # files always set it, to one value -- else CMAKE_SYSTEM_PROCESSOR.
    # See the file header for why not CMAKE_SYSTEM_PROCESSOR first.
    # Mapped explicitly rather than through HostArch.cmake's spelling
    # table, which files anything starting with "arm" -- arm64e, say --
    # under 32-bit ARM.
    set(_pmn_macos_arch "")
    if(CMAKE_OSX_ARCHITECTURES)
        list(LENGTH CMAKE_OSX_ARCHITECTURES _pmn_macos_arch_count)
        if(_pmn_macos_arch_count GREATER 1)
            message(FATAL_ERROR
                "CMAKE_OSX_ARCHITECTURES is '${CMAKE_OSX_ARCHITECTURES}' -- several "
                "architectures, i.e. a universal binary. A DIST_TARGET names exactly one "
                "architecture (macos-arm64-clang, macos-x64-clang): build each with its "
                "preset and combine the results with `lipo -create <arm64 file> <x64 file> "
                "-output <file>` if you need a single universal file.")
        elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
            set(_pmn_macos_arch "arm64")
        elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
            set(_pmn_macos_arch "x64")
        endif()
        set(_pmn_macos_arch_raw "CMAKE_OSX_ARCHITECTURES '${CMAKE_OSX_ARCHITECTURES}'")
    else()
        pmn_target_arch(_pmn_macos_arch _pmn_macos_arch_processor)
        set(_pmn_macos_arch_raw "CMAKE_SYSTEM_PROCESSOR '${_pmn_macos_arch_processor}'")
    endif()

    if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        if(_pmn_macos_arch)
            set(_pmn_detected_dist_target "macos-${_pmn_macos_arch}-clang")
        else()
            _pmn_dist_target_undetected(
                "unrecognized macOS architecture (${_pmn_macos_arch_raw}) -- set one "
                "explicitly: -DDIST_TARGET=<value>"
            )
        endif()
    elseif(DIST_TARGET)
        set(_pmn_detected_dist_target "")
    else()
        message(FATAL_ERROR
            "Could not auto-detect a DIST_TARGET for CXX compiler "
            "'${CMAKE_CXX_COMPILER_ID}' on macOS -- only Clang (Apple's, from the "
            "Xcode Command Line Tools, or LLVM's own) is a supported macOS target. "
            "Set one explicitly: -DDIST_TARGET=<value>\n"
            "Valid values: ${_pmn_valid_dist_targets_str}")
    endif()
else()
    # Linux: architecture comes from CMAKE_SYSTEM_PROCESSOR via
    # HostArch.cmake -- reliable here (unlike the raw cl.exe/clang-cl
    # case above). For a native build that is simply `uname -m`; for a
    # cross build the toolchain file (breeze/cmake/toolchains/) sets it to the
    # TARGET's architecture, which is exactly what should be labeled --
    # asking the host machine instead would call an aarch64 cross
    # build "x64".
    pmn_target_arch(_pmn_linux_arch)

    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        # Not a blind TOLOWER of CMAKE_CXX_COMPILER_ID: CMake's own ID
        # for GCC is "GNU" (a case-fold gives "gnu", which none of
        # PMN_VALID_DIST_TARGETS above or CMakePresets.json spell --
        # every one of them, and everyone outside CMake, calls it
        # "gcc"). Same reasoning the MSVC/clang-cl branch above
        # already applies to its own two compiler IDs.
        if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
            set(_pmn_linux_compiler_id "gcc")
        else()
            set(_pmn_linux_compiler_id "clang")
        endif()
        if(_pmn_linux_arch)
            set(_pmn_detected_dist_target "linux-${_pmn_linux_arch}-${_pmn_linux_compiler_id}")
        else()
            _pmn_dist_target_undetected(
                "unrecognized "
                "CMAKE_SYSTEM_PROCESSOR '${CMAKE_SYSTEM_PROCESSOR}' -- set one "
                "explicitly: -DDIST_TARGET=<value>"
            )
        endif()
    elseif(DIST_TARGET)
        set(_pmn_detected_dist_target "")
    else()
        message(FATAL_ERROR
            "Could not auto-detect a DIST_TARGET for CXX compiler "
            "'${CMAKE_CXX_COMPILER_ID}' -- set one explicitly: "
            "-DDIST_TARGET=<value>\n"
            "Valid values: ${_pmn_valid_dist_targets_str}")
    endif()
endif()

if(NOT DIST_TARGET)
    set(DIST_TARGET "${_pmn_detected_dist_target}")
    message(STATUS "DIST_TARGET not set -- auto-detected: ${DIST_TARGET}")
    message(STATUS "  (use a CMakePresets.json preset -- or -DCMAKE_TOOLCHAIN_FILE=breeze/cmake/toolchains/<target>.cmake -- to set it explicitly)")
else()
    if(NOT DIST_TARGET IN_LIST PMN_VALID_DIST_TARGETS)
        message(FATAL_ERROR
            "Unsupported DIST_TARGET: '${DIST_TARGET}'.\n"
            "Valid values: ${_pmn_valid_dist_targets_str}\n"
            "Tip: open CMakePresets.json in your IDE to select a preset, "
            "or pass -DDIST_TARGET=<value> on the command line.")
    endif()

    if(NOT DIST_TARGET STREQUAL _pmn_detected_dist_target)
        # This is the check described in the file header: a DIST_TARGET
        # that disagrees with the compiler CMake actually found.
        if(_pmn_detected_dist_target)
            set(_pmn_detected_desc "'${_pmn_detected_dist_target}'")
        else()
            set(_pmn_detected_desc "none of the values this project recognizes")
        endif()

        # The fix depends on where DIST_TARGET came from. From a
        # toolchain file the compiler was already chosen to match, so
        # something overrode it afterwards; from a bare -DDIST_TARGET
        # nothing ever chose a compiler at all.
        #
        # (string(CONCAT) rather than a multi-value set(): a list would
        # swallow every ";" in the text when expanded into message().)
        if(_pmn_dist_target_source STREQUAL "toolchain")
            string(CONCAT _pmn_fix
                "The toolchain file picked its own compiler, so this means it was overridden "
                "afterwards -- most likely an explicit -DCMAKE_CXX_COMPILER=... (on macOS "
                "also -DCMAKE_OSX_ARCHITECTURES=...), or a CMakeCache.txt left in this "
                "build directory by an earlier configure for a different target.\n"
                "Remove that override, or configure into a fresh build directory. The default "
                "layout already gives every preset its own (out/build/<preset>); "
                "${CMAKE_BINARY_DIR} is being shared between targets.")
        else()
            string(CONCAT _pmn_fix
                "-DDIST_TARGET=... only labels the build; it does not select a compiler. Use "
                "the toolchain file made for that target, which sets both together:\n"
                "  -DCMAKE_TOOLCHAIN_FILE=${CMAKE_SOURCE_DIR}/breeze/cmake/toolchains/${DIST_TARGET}.cmake\n"
                "or the matching CMakePresets.json preset, which selects it for you:\n"
                "  cmake --preset ${DIST_TARGET}")
        endif()

        # Some compilers can't be redirected from CMake at all; say so
        # rather than only pointing at a toolchain file that cannot
        # help.
        set(_pmn_family_hint "")
        if(DIST_TARGET MATCHES "-msvc$")
            set(_pmn_family_hint
                "\ncl.exe's architecture is decided by the Visual Studio developer environment \
it is run from, not by CMake: open the matching Native Tools / Cross Tools Command Prompt \
(vcvarsall.bat), or build with breeze\\scripts\\build.bat, which does that for you.")
        elseif(DIST_TARGET MATCHES "^windows-(x64|arm64)-clang$")
            set(_pmn_family_hint
                "\nThis GNU-style Clang gets its target from the shell environment it runs in: \
use an MSYS2 CLANG64 (x64) or CLANGARM64 (ARM64) shell, or build with breeze\\scripts\\build.bat, which puts that toolchain first on PATH.")
        endif()

        message(FATAL_ERROR
            "DIST_TARGET is '${DIST_TARGET}', but the CXX compiler CMake actually found -- "
            "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} -- auto-detects to "
            "${_pmn_detected_desc}, not '${DIST_TARGET}'.\n"
            "${_pmn_fix}\n"
            "${_pmn_family_hint}")
    endif()

    message(STATUS "DIST_TARGET    = ${DIST_TARGET}")
endif()

# Platform / compiler metadata from DIST_TARGET.
if(DIST_TARGET STREQUAL "linux-x64-gcc")
    set(PLATFORM "linux")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "gcc")
elseif(DIST_TARGET STREQUAL "linux-x64-clang")
    set(PLATFORM "linux")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "linux-arm64-gcc")
    set(PLATFORM "linux")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "gcc")
elseif(DIST_TARGET STREQUAL "linux-arm64-clang")
    set(PLATFORM "linux")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "linux-arm32-gcc")
    set(PLATFORM "linux")
    set(ARCHITECTURE "arm32")
    set(COMPILER_ID "gcc")
elseif(DIST_TARGET STREQUAL "linux-arm32-clang")
    set(PLATFORM "linux")
    set(ARCHITECTURE "arm32")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "macos-arm64-clang")
    set(PLATFORM "macos")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "macos-x64-clang")
    set(PLATFORM "macos")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "windows-x64-msvc")
    set(PLATFORM "windows")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "msvc")
elseif(DIST_TARGET STREQUAL "windows-arm64-msvc")
    set(PLATFORM "windows")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "msvc")
elseif(DIST_TARGET STREQUAL "windows-x64-clang-cl")
    set(PLATFORM "windows")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "clang-cl")
elseif(DIST_TARGET STREQUAL "windows-arm64-clang-cl")
    set(PLATFORM "windows")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "clang-cl")
elseif(DIST_TARGET STREQUAL "windows-x64-clang")
    set(PLATFORM "windows")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "windows-arm64-clang")
    set(PLATFORM "windows")
    set(ARCHITECTURE "arm64")
    set(COMPILER_ID "clang")
elseif(DIST_TARGET STREQUAL "windows-x86-mingw32")
    set(PLATFORM "windows")
    set(ARCHITECTURE "x86")
    set(COMPILER_ID "mingw32")
elseif(DIST_TARGET STREQUAL "windows-x64-mingw64")
    set(PLATFORM "windows")
    set(ARCHITECTURE "x64")
    set(COMPILER_ID "mingw64")
else()
    message(FATAL_ERROR
        "Unsupported DIST_TARGET: '${DIST_TARGET}'.\n"
        "Valid values: ${_pmn_valid_dist_targets_str}\n"
        "Tip: open CMakePresets.json in your IDE to select a preset, "
        "or pass -DDIST_TARGET=<value> on the command line.")
endif()

message(STATUS "Platform     = ${PLATFORM}")
message(STATUS "Architecture = ${ARCHITECTURE}")
message(STATUS "Compiler     = ${COMPILER_ID} (${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION})")
