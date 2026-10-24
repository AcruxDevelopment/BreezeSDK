# =============================================================================
# toolchains/_common.cmake
#
# Helpers shared by the per-DIST_TARGET toolchain files next to this one
# (linux-x64-gcc.cmake, windows-arm64-clang-cl.cmake, ...). This is not a
# toolchain file itself -- nothing should point CMAKE_TOOLCHAIN_FILE here.
#
# Why toolchain files at all
# --------------------------
# A toolchain file is CMake's own mechanism for "build with THIS compiler
# for THIS target". CMake reads it before project() detects anything, so
# the compiler and target are settled first instead of being discovered
# and then cross-checked after the fact. Every CMakePresets.json preset
# points at the toolchain file with its own name (see the "base" preset),
# and each file does three things:
#
#   1. Declares which DIST_TARGET it is for (PMN_TOOLCHAIN_DIST_TARGET), so
#      TargetSelection.cmake no longer has to guess from the compiler and
#      can't be handed a mislabeled build -- the label and the compiler
#      travel together.
#   2. Picks the compiler (and, for clang-cl, the --target triple).
#   3. Where the target isn't the machine running CMake, sets up a real
#      cross-compile: CMAKE_SYSTEM_NAME / CMAKE_SYSTEM_PROCESSOR, restricts
#      find_package/find_library to the target's sysroot (so a host-arch
#      library is never linked into a foreign-arch binary), and registers
#      an emulator (qemu-user / wine) if one is installed, so ctest can run
#      what it just built.
#
# Two behaviors worth knowing, both verified rather than assumed:
#
#   * CMAKE_SYSTEM_NAME is only set when the build really is a cross build.
#     Setting it -- even to the value the host already has -- flips
#     CMAKE_CROSSCOMPILING to TRUE, which changes how try_run and
#     several third-party CMakeLists behave. Native builds leave it alone.
#
#   * A compiler chosen here never overrides an explicit
#     -DCMAKE_CXX_COMPILER=... on the command line (an unguarded set()
#     in a toolchain file silently would). The toolchain DOES beat a stray
#     CXX environment variable, since a target called "linux-x64-gcc"
#     shouldn't be built with whatever CXX=clang++ happens to be exported.
#
#   * macOS is deliberately not a "cross build" even when the architecture
#     differs from the machine's (an x86_64 build on an Apple Silicon Mac):
#     Apple's clang is one multi-architecture compiler, so that is a
#     different -arch flag, not a different compiler. pmn_macos_toolchain()
#     leaves CMAKE_SYSTEM_NAME alone and pins CMAKE_OSX_ARCHITECTURES.
#
# Toolchain files are read more than once per configure (CMake re-reads
# them for every try_compile), so everything here must stay cheap and
# idempotent.
# =============================================================================

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/../HostArch.cmake")

# -----------------------------------------------------------------------
# pmn_warn_once(<key> <text>...)
#
# message(WARNING ...) at most once per configure. This file is read again
# for the same scope (see the note at the top), so a plain warning would
# print as many times as the file is read -- and the same multi-line
# warning twice in a row reads as two problems. The <text> arguments are
# joined with nothing between them, like message()'s own, so they must not
# contain a semicolon (a list separator, which would be lost).
# -----------------------------------------------------------------------
function(pmn_warn_once _pmn_key)
    get_property(_pmn_seen GLOBAL PROPERTY "PMN_WARNED_${_pmn_key}")
    if(NOT _pmn_seen)
        set_property(GLOBAL PROPERTY "PMN_WARNED_${_pmn_key}" TRUE)
        string(JOIN "" _pmn_text ${ARGN})
        message(WARNING "${_pmn_text}")
    endif()
endfunction()

# -----------------------------------------------------------------------
# pmn_check_msvc_target(<arch>)
#
# For the presets that link against MSVC's runtime libraries (msvc and
# clang-cl): asks the Visual Studio developer prompt CMake runs in what it is
# set up for, before CMake's own compiler test fails with an error that
# names neither -- "cannot open msvcrt.lib", or lld-link's "could not open
# 'msvcrtd.lib'". Both are warnings: the configure carries on, and either
# works anyway or fails right below the explanation.
#
#   * VSCMD_ARG_TGT_ARCH, which the developer prompts set, names another
#     target than the preset builds for.
#   * VCToolsInstallDir, set by the same prompts, has no lib/<arch>/msvcrt.lib:
#     the component that provides the target is not installed. From an x64
#     machine ARM64 is a cross build and needs the ARM64 build tools; vcvarsall
#     still "succeeds" without them, leaving the host's x64 cl first on PATH
#     and the ARM64 library directory in LIB.
# -----------------------------------------------------------------------
function(pmn_check_msvc_target _pmn_arch)
    if(DEFINED ENV{VSCMD_ARG_TGT_ARCH} AND NOT "$ENV{VSCMD_ARG_TGT_ARCH}" STREQUAL "${_pmn_arch}")
        pmn_warn_once(msvc-target-arch
            "This Visual Studio developer prompt targets $ENV{VSCMD_ARG_TGT_ARCH}, but the "
            "'${PMN_TOOLCHAIN_DIST_TARGET}' toolchain builds for ${_pmn_arch}. Open the matching prompt "
            "(for example an x64 Native Tools or x64_arm64 Cross Tools Command Prompt), or build with "
            "breeze\\scripts\\build.bat, which enters the right environment for you, and delete the "
            "build directory after switching.")
    endif()
    if(DEFINED ENV{VCToolsInstallDir} AND NOT EXISTS "$ENV{VCToolsInstallDir}/lib/${_pmn_arch}/msvcrt.lib")
        pmn_warn_once(msvc-target-libs
            "The MSVC runtime libraries for ${_pmn_arch} are missing: $ENV{VCToolsInstallDir}lib/${_pmn_arch}/msvcrt.lib "
            "does not exist, so linking will fail with 'cannot open msvcrt.lib'. Add the component for "
            "${_pmn_arch} in the Visual Studio Installer (Modify, Individual components): \"MSVC ... C++ "
            "ARM64/ARM64EC build tools (Latest)\" for arm64, which an x64 machine needs too because it "
            "cross-compiles, or \"MSVC ... C++ x64/x86 build tools (Latest)\" for x64. breeze\\scripts\\setup.bat "
            "offers to add the ARM64 one.")
    endif()
endfunction()

# -----------------------------------------------------------------------
# pmn_note_once(<key> <text>...)
#
# message(STATUS ...) at most once per configure -- pmn_warn_once's quiet
# sibling, for information that is useful in the log but is not a problem
# (which target sysroot is in use; that there is none).
# -----------------------------------------------------------------------
function(pmn_note_once _pmn_key)
    get_property(_pmn_seen GLOBAL PROPERTY "PMN_NOTED_${_pmn_key}")
    if(NOT _pmn_seen)
        set_property(GLOBAL PROPERTY "PMN_NOTED_${_pmn_key}" TRUE)
        string(JOIN "" _pmn_text ${ARGN})
        message(STATUS "${_pmn_text}")
    endif()
endfunction()

# -----------------------------------------------------------------------
# pmn_find_sysroot(<x64|arm64|arm32> <dir-var> <why-var>)
#
# Which TARGET SYSROOT, if any, a Linux cross build should use: a directory
# laid out like the target machine's root filesystem (usr/include, usr/lib,
# ...) that holds the libraries and headers the project's dependencies need
# beyond the C/C++ runtime -- X11, OpenGL, ALSA and the like. A cross
# compiler package brings only the runtime (/usr/<triplet>), so a dependency
# that asks for anything else stops with "Could NOT find X11" (raylib's GLFW
# does exactly that on Linux). In order:
#
#   1. -DCMAKE_SYSROOT=<dir> on the command line or in a preset: used as is.
#   2. <project>/.cache/sysroots/linux-<arch>, if that directory exists
#      (linux-arm64, linux-arm32, linux-x64): one per architecture, shared
#      by the gcc and clang presets, found without any option -- which is
#      what lets several cross presets be built one after the other.
#
# Both outputs are empty when there is none. A directory that does not exist
# is an error; one without usr/ in it only a warning (the usual mistake is
# pointing at the folder that CONTAINS the root filesystem).
# -----------------------------------------------------------------------
function(pmn_find_sysroot _pmn_arch _pmn_out_dir _pmn_out_why)
    set(_pmn_dir "")
    set(_pmn_why "")
    # The cache, not the plain variable: a toolchain file sets a plain
    # CMAKE_SYSROOT itself (below), and a re-read must not mistake that for
    # the user's choice.
    if(DEFINED CACHE{CMAKE_SYSROOT} AND NOT "$CACHE{CMAKE_SYSROOT}" STREQUAL "")
        set(_pmn_dir "$CACHE{CMAKE_SYSROOT}")
        set(_pmn_why "CMAKE_SYSROOT")
    else()
        get_filename_component(_pmn_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
        if(IS_DIRECTORY "${_pmn_root}/.cache/sysroots/linux-${_pmn_arch}")
            set(_pmn_dir "${_pmn_root}/.cache/sysroots/linux-${_pmn_arch}")
            set(_pmn_why ".cache/sysroots/linux-${_pmn_arch}")
        endif()
    endif()
    if(_pmn_dir)
        if(NOT IS_DIRECTORY "${_pmn_dir}")
            message(FATAL_ERROR
                "The target sysroot '${_pmn_dir}' (${_pmn_why}) is not a directory.\n"
                "Point CMAKE_SYSROOT at a root filesystem for the target (it has usr/include and "
                "usr/lib in it), or drop the option. See \"Cross builds and system libraries\" "
                "in the README.")
        endif()
        if(NOT IS_DIRECTORY "${_pmn_dir}/usr")
            pmn_warn_once(sysroot-layout
                "The target sysroot '${_pmn_dir}' has no usr/ directory, so it does not look like "
                "a root filesystem -- is it the folder that contains one? Headers are looked for in "
                "<sysroot>/usr/include and libraries in <sysroot>/usr/lib.")
        endif()
    endif()
    set(${_pmn_out_dir} "${_pmn_dir}" PARENT_SCOPE)
    set(${_pmn_out_why} "${_pmn_why}" PARENT_SCOPE)
endfunction()

# -----------------------------------------------------------------------
# pmn_use_sysroot(<dir> <triplet>)
#
# Makes <dir> the target's root for this build:
#
#   * CMAKE_SYSROOT -- CMake passes --sysroot= to GCC and Clang, and
#     find_package/find_library/find_path search under it. It also goes
#     FIRST in CMAKE_FIND_ROOT_PATH, ahead of the cross compiler's own
#     /usr/<triplet>, so what the target really has wins.
#   * CMAKE_LIBRARY_ARCHITECTURE, when the sysroot is Debian-style
#     multiarch (libraries in usr/lib/<triplet>/): without it find_library
#     doesn't look there.
#   * pkg-config: PKG_CONFIG_SYSROOT_DIR / PKG_CONFIG_LIBDIR point at the
#     sysroot's .pc files only, and PKG_CONFIG_PATH is dropped, so
#     pkg_check_modules() answers for the target instead of the host (whose
#     .pc files would hand the compiler x86 include paths and libraries).
#
# A macro, like the rest of this file's helpers that set variables: the
# toolchain file's own scope is where they must land.
# -----------------------------------------------------------------------
macro(pmn_use_sysroot _pmn_sr_dir _pmn_sr_triplet)
    set(CMAKE_SYSROOT "${_pmn_sr_dir}")
    list(PREPEND CMAKE_FIND_ROOT_PATH "${_pmn_sr_dir}")
    list(REMOVE_DUPLICATES CMAKE_FIND_ROOT_PATH)
    if(NOT CMAKE_LIBRARY_ARCHITECTURE AND IS_DIRECTORY "${_pmn_sr_dir}/usr/lib/${_pmn_sr_triplet}")
        set(CMAKE_LIBRARY_ARCHITECTURE "${_pmn_sr_triplet}")
    endif()
    set(_pmn_sr_pc "")
    foreach(_pmn_sr_sub
            usr/lib/pkgconfig
            usr/lib64/pkgconfig
            usr/lib/${_pmn_sr_triplet}/pkgconfig
            usr/share/pkgconfig)
        list(APPEND _pmn_sr_pc "${_pmn_sr_dir}/${_pmn_sr_sub}")
    endforeach()
    list(JOIN _pmn_sr_pc ":" _pmn_sr_pc_joined)
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "${_pmn_sr_dir}")
    set(ENV{PKG_CONFIG_LIBDIR} "${_pmn_sr_pc_joined}")
    unset(ENV{PKG_CONFIG_PATH})
endmacro()

# -----------------------------------------------------------------------
# pmn_toolchain_target(<DIST_TARGET>)
#
# Declares which DIST_TARGET the calling toolchain file is for.
# TargetSelection.cmake reads PMN_TOOLCHAIN_DIST_TARGET and uses it as
# DIST_TARGET (an explicit, different -DDIST_TARGET is a FATAL_ERROR).
# -----------------------------------------------------------------------
macro(pmn_toolchain_target _pmn_tc_dist_target)
    set(PMN_TOOLCHAIN_DIST_TARGET "${_pmn_tc_dist_target}")
endmacro()

# -----------------------------------------------------------------------
# pmn_use_compilers(<cxx-program> <c-program> "<install hint>")
#
# Selects the C++ (and C) compiler by program name, resolved on PATH to an
# absolute path so it's identical in every try_compile. Skipped for
# whichever of CMAKE_CXX_COMPILER / CMAKE_C_COMPILER the user already
# chose explicitly.
#
# A missing C++ compiler is a FATAL_ERROR here, with the install hint,
# rather than CMake's generic "compiler ... is not a full path and was not
# found in the PATH". The C compiler is set too even though the project
# is C++-only: if someone later adds a C source or a C dependency, CMake
# must not silently auto-detect the HOST's cc for a cross build and emit
# wrong-architecture objects. If the C compiler can't be found, its bare
# name is set anyway so that mistake fails loudly.
#
# A function (not a macro) on purpose: the hint is free text that a macro
# would evaluate twice, and its temporaries stay out of the caller's scope.
# PARENT_SCOPE lands in the toolchain file's own scope because the macros
# below, which call this, don't create one.
# -----------------------------------------------------------------------
function(pmn_use_compilers CXX_PROGRAM C_PROGRAM HINT)
    if(NOT CMAKE_CXX_COMPILER)
        find_program(_pmn_tc_cxx_path NAMES "${CXX_PROGRAM}" NO_CACHE)
        if(NOT _pmn_tc_cxx_path)
            message(FATAL_ERROR
                "The '${PMN_TOOLCHAIN_DIST_TARGET}' toolchain needs the C++ compiler "
                "'${CXX_PROGRAM}', but it isn't on PATH.\n${HINT}\n"
                "(Or name a different compiler explicitly: -DCMAKE_CXX_COMPILER=<path>)")
        endif()
        set(CMAKE_CXX_COMPILER "${_pmn_tc_cxx_path}" PARENT_SCOPE)
    endif()
    if(NOT CMAKE_C_COMPILER)
        find_program(_pmn_tc_c_path NAMES "${C_PROGRAM}" NO_CACHE)
        if(_pmn_tc_c_path)
            set(CMAKE_C_COMPILER "${_pmn_tc_c_path}" PARENT_SCOPE)
        else()
            set(CMAKE_C_COMPILER "${C_PROGRAM}" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# -----------------------------------------------------------------------
# pmn_cross_target(<system-name> <system-processor> <find-root>)
#
# Turns this into a cross build. <find-root> is the target's sysroot-like
# prefix (Debian/Ubuntu put a cross toolchain's target headers and
# libraries under /usr/<triplet>); an explicit -DCMAKE_SYSROOT=... and
# -DCMAKE_FIND_ROOT_PATH=... from the user are kept and extended, not
# replaced.
#
# The four MODE settings are the standard cross-compile split: programs
# (Doxygen, a pinned ninja, ...) come from the HOST; libraries, headers
# and CMake packages only from the target's root. That last one is what
# makes FetchContent's find_package(fmt) miss the host's libfmt -- which
# would link, then fail at load time as the wrong architecture -- and fall
# through to fetching and building fmt for the target.
# -----------------------------------------------------------------------
macro(pmn_cross_target _pmn_tc_system _pmn_tc_processor _pmn_tc_root)
    set(CMAKE_SYSTEM_NAME "${_pmn_tc_system}")
    set(CMAKE_SYSTEM_PROCESSOR "${_pmn_tc_processor}")
    list(APPEND CMAKE_FIND_ROOT_PATH "${_pmn_tc_root}")
    list(REMOVE_DUPLICATES CMAKE_FIND_ROOT_PATH)
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
endmacro()

# -----------------------------------------------------------------------
# pmn_cross_emulator(<program>|"<program>;<program>" [<args>...])
#
# Registers the first of the given program names that is installed
# (qemu-aarch64, or "wine;wine64", ...) as CMAKE_CROSSCOMPILING_EMULATOR,
# so ctest and add_custom_command(COMMAND <target>) can run a
# foreign-architecture binary, and so can breeze/scripts/run.sh. Silent if none is
# installed -- the build itself doesn't need one. An emulator the user set
# explicitly is left alone.
#
# It's a cache entry rather than a plain variable so that breeze/scripts/run.sh,
# which runs long after configure, can read it back out of CMakeCache.txt.
# CMake treats a cached CMAKE_CROSSCOMPILING_EMULATOR exactly like a
# variable set here (it's also what -DCMAKE_CROSSCOMPILING_EMULATOR=...
# creates). Only set once found, so installing qemu later still gets
# picked up on the next configure.
# -----------------------------------------------------------------------
function(pmn_cross_emulator PROGRAM)
    if(NOT CMAKE_CROSSCOMPILING_EMULATOR)
        find_program(_pmn_tc_emulator_path NAMES ${PROGRAM} NO_CACHE)
        if(_pmn_tc_emulator_path)
            set(CMAKE_CROSSCOMPILING_EMULATOR "${_pmn_tc_emulator_path}" ${ARGN}
                CACHE STRING "Emulator used to run cross-compiled executables (ctest, breeze/scripts/run.sh)")
        endif()
    endif()
endfunction()

# -----------------------------------------------------------------------
# pmn_linux_toolchain(<x64|arm64|arm32> <gcc|clang>)
#
# One implementation behind all six linux-* toolchain files.
#
# Native or cross is decided by comparing the requested architecture with
# the machine CMake is running on (`uname -m`, via HostArch.cmake): the same
# linux-arm64-gcc preset builds natively on ARM64 hardware with the ordinary
# g++, and cross-builds from an x64 machine with aarch64-linux-gnu-g++.
#
#   GCC   cross: <triplet>-g++ -- breeze/scripts/setup.sh installs this for you on
#                apt (Debian/Ubuntu), pacman (Arch, arm64 only), and dnf
#                (Fedora/RHEL, AArch64/32-bit ARM only, from a COPR since
#                Fedora's own cross-gcc ships no libstdc++) -- see its own
#                "why" text for exactly what and why, including the gaps:
#                x86-64-from-arm64 has no known working package anywhere
#                yet, and 32-bit ARM on Arch is AUR-only (x64 hosts only).
#   Clang cross: clang++ --target=<triplet>, which additionally needs the
#                target's libstdc++/libc: the GCC cross package above
#                provides them under /usr/<triplet>, or pass
#                -DCMAKE_SYSROOT=<sysroot>. <triplet> is the one the cross
#                g++ says it was built for (-dumpmachine) when that is the
#                same architecture -- the preset's own default otherwise.
#
# Both families check what the installed cross compiler tells them instead of
# trusting it: a sysroot it reports that isn't on disk is dropped, with a
# warning; a GCC that can't find the assembler for its own target (and would
# quietly run the host's) is warned about up front, before CMake's compiler
# test fails with an error that names neither. Both are the signature of a
# compiler installed beside binutils or a C library from a different package
# set -- see "32-bit ARM on Arch" in the README.
#
# A cross build can also have a TARGET SYSROOT -- a root filesystem for the
# target with the libraries and headers its dependencies need beyond the
# C/C++ runtime (X11, OpenGL, ALSA, ...), which no cross compiler package
# ships: -DCMAKE_SYSROOT=<dir>, or just a directory at
# .cache/sysroots/linux-<arch>. pmn_find_sysroot / pmn_use_sysroot below
# say what it changes; without one the configure says so in its first lines,
# and a dependency that wants such a library stops with "Could NOT find".
#
# One unusual case falls outside this: a 32-bit userland running on a
# 64-bit ARM kernel reports aarch64 from `uname -m` while its ordinary g++
# already builds 32-bit code. For that, pass -DCMAKE_CXX_COMPILER=g++ (the
# build is then labeled arm32, correctly, but is treated as a cross build).
#
# NOTE for anyone editing the macros in this file: a macro's parameters
# are textual substitutions, so every use inside if() is quoted --
# unquoted, `if(x64 STREQUAL ...)` would treat "x64" as a variable name.
# -----------------------------------------------------------------------
macro(pmn_linux_toolchain _pmn_tc_arch _pmn_tc_family)
    if("${_pmn_tc_arch}" STREQUAL "x64")
        set(_pmn_tc_processor "x86_64")
        set(_pmn_tc_triplet   "x86_64-linux-gnu")
        set(_pmn_tc_gcc_pkg   "g++-x86-64-linux-gnu")
        set(_pmn_tc_qemu      "qemu-x86_64")
    elseif("${_pmn_tc_arch}" STREQUAL "arm64")
        set(_pmn_tc_processor "aarch64")
        set(_pmn_tc_triplet   "aarch64-linux-gnu")
        set(_pmn_tc_gcc_pkg   "g++-aarch64-linux-gnu")
        set(_pmn_tc_qemu      "qemu-aarch64")
    elseif("${_pmn_tc_arch}" STREQUAL "arm32")
        set(_pmn_tc_processor "arm")
        set(_pmn_tc_triplet   "arm-linux-gnueabihf")
        set(_pmn_tc_gcc_pkg   "g++-arm-linux-gnueabihf")
        set(_pmn_tc_qemu      "qemu-arm")
    else()
        message(FATAL_ERROR "pmn_linux_toolchain: unknown architecture '${_pmn_tc_arch}'")
    endif()

    pmn_host_arch(_pmn_tc_host_arch)
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND "${_pmn_tc_host_arch}" STREQUAL "${_pmn_tc_arch}")
        # Native: this machine already IS the target.
        if("${_pmn_tc_family}" STREQUAL "gcc")
            pmn_use_compilers(g++ gcc "Run breeze/scripts/setup.sh to install one, or by hand -- e.g. on Debian/Ubuntu: sudo apt install g++")
        else()
            pmn_use_compilers(clang++ clang "Run breeze/scripts/setup.sh to install one, or by hand -- e.g. on Debian/Ubuntu: sudo apt install clang")
        endif()
    else()
        # Cross.
        pmn_cross_target(Linux "${_pmn_tc_processor}" "/usr/${_pmn_tc_triplet}")

        # The actual sysroot the installed cross package for this triplet
        # was built with -- nothing meaningful on a flat layout (apt's,
        # and pacman's -- see the "/" normalization below for what their
        # cross-gcc actually prints), a real path on a nested one (dnf's
        # COPR toolchain, which mirrors Fedora's own cross-gcc convention:
        # /usr/<triplet>/sys-root). Queried once, up front, because both
        # families need it below: GCC already knows its own paths for
        # compiling and linking, but qemu-user doesn't -- given the flat
        # guess on a nested layout, it looks for the target's dynamic
        # linker (ld-linux-aarch64.so.1, etc.) in the wrong place and
        # doesn't find it ("Could not open '/lib/ld-linux-aarch64.so.1'",
        # confirmed on Fedora) -- the same class of problem as Clang's
        # link-time one below, just at run time and for either family.
        # Clang additionally can't compile at all on a nested layout
        # without being told the same thing explicitly -- see below.
        find_program(_pmn_tc_cross_gxx NAMES "${_pmn_tc_triplet}-g++" NO_CACHE)
        set(_pmn_tc_cross_sysroot "")
        set(_pmn_tc_cross_machine "")
        if(_pmn_tc_cross_gxx)
            execute_process(
                COMMAND "${_pmn_tc_cross_gxx}" -print-sysroot
                OUTPUT_VARIABLE _pmn_tc_cross_sysroot
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            # A cross-gcc that was never configured with a sysroot of its
            # own (apt's -- confirmed on Debian, where this broke qemu for
            # every cross preset the moment this query was added) doesn't
            # print an empty line for that: it prints "/", gcc's ordinary
            # "no special sysroot" default. That is not a sysroot to
            # hand anyone -- as qemu's -L it means "the target's root
            # filesystem is THIS machine's", so it goes looking for the
            # target's dynamic linker in the host's own /lib
            # ("Could not open '/lib/ld-linux-aarch64.so.1'") -- and as
            # Clang's --sysroot it points header and library lookup at the
            # host's /usr too. Treated exactly like empty from here on.
            if(_pmn_tc_cross_sysroot STREQUAL "/")
                set(_pmn_tc_cross_sysroot "")
            endif()
            # A sysroot the compiler reports but that isn't on disk is what a
            # toolchain whose parts don't belong together looks like: GCC
            # relocates its configured sysroot next to itself, but only
            # where the relocated directory exists -- otherwise it keeps the
            # configured, unrelocated path. Seen with ARM's prebuilt GCC
            # (built with --with-sysroot=/arm-none-linux-gnueabihf/libc)
            # installed beside a binutils and glibc from somewhere else:
            # -print-sysroot says "/arm-none-linux-gnueabihf/libc", nothing is
            # there, and Clang -- handed that as --sysroot -- fell back to the
            # HOST's crt files and failed to link ("Scrt1.o: file not
            # recognized"). A path that doesn't exist is worse than none, so
            # it is dropped, and said so.
            if(_pmn_tc_cross_sysroot AND NOT IS_DIRECTORY "${_pmn_tc_cross_sysroot}")
                pmn_warn_once(sysroot
                    "The cross compiler ${_pmn_tc_cross_gxx} reports the sysroot "
                    "'${_pmn_tc_cross_sysroot}', which does not exist, so it is ignored. That is "
                    "what a toolchain whose parts don't belong together looks like -- a compiler "
                    "from one package set, binutils or the C library from another -- and linking "
                    "will most likely fail (\"file not recognized\", a missing crt1.o or libc). "
                    "Install the compiler, binutils and C library for this target from the same "
                    "source: breeze/scripts/setup.sh does that where it can (on Arch, for 32-bit ARM, "
                    "see \"32-bit ARM on Arch\" in the README), or pass -DCMAKE_SYSROOT=<the "
                    "target's root filesystem>.")
                set(_pmn_tc_cross_sysroot "")
            endif()
            # The triple this compiler itself was built for -- not necessarily
            # the one the preset is named after: ARM's own GCC release is
            # arm-none-linux-gnueabihf, and its libraries live under
            # lib/gcc/arm-none-linux-gnueabihf/, which Clang only finds when
            # told that exact triple. (Debian's, Fedora's COPR and Arch's own
            # cross compilers all say the same triple the preset uses, so
            # nothing changes for them.)
            execute_process(
                COMMAND "${_pmn_tc_cross_gxx}" -dumpmachine
                OUTPUT_VARIABLE _pmn_tc_cross_machine
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
        endif()
        # What the cross compiler package itself reports (or /usr/<triplet>):
        # the root qemu runs the result against unless a target sysroot of the
        # user's (below) can do it better.
        if(_pmn_tc_cross_sysroot)
            set(_pmn_tc_emulator_root "${_pmn_tc_cross_sysroot}")
        else()
            set(_pmn_tc_emulator_root "/usr/${_pmn_tc_triplet}")
        endif()

        # A target sysroot of the user's, if there is one: where the libraries
        # and headers that a cross compiler package doesn't ship (X11,
        # OpenGL, ALSA, ...) come from. See pmn_find_sysroot for where it is
        # looked for and pmn_use_sysroot for what it changes. It replaces
        # the compiler-reported sysroot for Clang's flags below, and for
        # qemu's -L when it can run programs, i.e. holds the target's dynamic
        # loader -- a partial copy (headers and link libraries only) must not
        # take qemu's root away from the toolchain's.
        pmn_find_sysroot("${_pmn_tc_arch}" _pmn_tc_sysroot _pmn_tc_sysroot_why)

        # A build directory keeps what CMake detected about the compiler -- its library
        # directories, the multiarch name -- from the FIRST configure on. A sysroot
        # added, changed or removed since then leaves that stale, and the link lines
        # go quietly wrong (a stray -L<sysroot>/usr/lib ahead of the compiler's own,
        # say). The usual way to get here: a configure stops on a library the
        # target's root lacks, the sysroot that has it is put in place, and the same
        # build directory is configured again. So stop, and say what to do.
        if(_pmn_tc_sysroot)
            set(_pmn_tc_sysroot_id "${_pmn_tc_sysroot}")
        else()
            set(_pmn_tc_sysroot_id "(none)")
        endif()
        if(DEFINED CACHE{PMN_TC_SYSROOT_USED} AND NOT "$CACHE{PMN_TC_SYSROOT_USED}" STREQUAL "${_pmn_tc_sysroot_id}")
            message(FATAL_ERROR
                "The target sysroot changed since this build directory was first configured: "
                "it was $CACHE{PMN_TC_SYSROOT_USED}, it is now ${_pmn_tc_sysroot_id}.\n"
                "CMake keeps what it detected about the compiler in the build directory, and "
                "that was detected against the old sysroot, so the link lines would go subtly "
                "wrong. Delete the build directory and configure again:\n"
                "  rm -rf ${CMAKE_BINARY_DIR}")
        endif()
        set(PMN_TC_SYSROOT_USED "${_pmn_tc_sysroot_id}" CACHE INTERNAL
            "The target sysroot this build directory was first configured with")
        if(_pmn_tc_sysroot)
            pmn_use_sysroot("${_pmn_tc_sysroot}" "${_pmn_tc_triplet}")
            pmn_note_once(sysroot "Target sysroot: ${_pmn_tc_sysroot} (${_pmn_tc_sysroot_why})")
            set(_pmn_tc_cross_sysroot "${_pmn_tc_sysroot}")
            file(GLOB _pmn_tc_loaders
                "${_pmn_tc_sysroot}/lib/ld-linux*"
                "${_pmn_tc_sysroot}/lib64/ld-linux*"
                "${_pmn_tc_sysroot}/usr/lib/ld-linux*"
                "${_pmn_tc_sysroot}/usr/lib64/ld-linux*"
                "${_pmn_tc_sysroot}/lib/${_pmn_tc_triplet}/ld-linux*"
                "${_pmn_tc_sysroot}/usr/lib/${_pmn_tc_triplet}/ld-linux*")
            if(_pmn_tc_loaders)
                set(_pmn_tc_emulator_root "${_pmn_tc_sysroot}")
            endif()
        else()
            pmn_note_once(no-sysroot
                "Cross build without a target sysroot: only ${_pmn_tc_emulator_root} is searched for \
libraries and headers, so a dependency that needs system libraries (X11, OpenGL, ALSA, ...) will \
stop with \"Could NOT find ...\". Put a root filesystem for the target in \
.cache/sysroots/linux-${_pmn_tc_arch}, or pass -DCMAKE_SYSROOT=<dir> -- see \"Cross builds and \
system libraries\" in the README.")
        endif()

        if("${_pmn_tc_family}" STREQUAL "gcc")
            pmn_use_compilers("${_pmn_tc_triplet}-g++" "${_pmn_tc_triplet}-gcc"
                "Run breeze/scripts/setup.sh to install the cross compiler for your package manager (apt for every target; dnf for AArch64 and 32-bit ARM, from a COPR; pacman for AArch64, and for 32-bit ARM from the AUR, which breeze/scripts/setup.sh offers -- see its own \"why\" text for details), or by hand -- e.g. on Debian/Ubuntu: sudo apt install ${_pmn_tc_gcc_pkg}")
            # A cross GCC finds the assembler for its target in its own
            # directories (<prefix>/<target>/bin/as and the like); when it
            # doesn't, it quietly runs whatever `as` is on PATH -- the HOST's
            # -- and the first file fails with an error that names neither
            # (x86's `as` says: "invalid -march= option: `armv7-a+simd'").
            # -print-prog-name=as says what GCC would run: an absolute path
            # when it found one, the bare name when it didn't.
            if(_pmn_tc_cross_gxx AND "${CMAKE_CXX_COMPILER}" STREQUAL "${_pmn_tc_cross_gxx}")
                execute_process(
                    COMMAND "${_pmn_tc_cross_gxx}" -print-prog-name=as
                    OUTPUT_VARIABLE _pmn_tc_cross_as
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
                if(_pmn_tc_cross_as AND NOT _pmn_tc_cross_as MATCHES "/")
                    pmn_warn_once(assembler
                        "The cross compiler ${_pmn_tc_cross_gxx} cannot find the assembler for its own "
                        "target (-print-prog-name=as gives the bare name '${_pmn_tc_cross_as}'), so "
                        "it will run the HOST's assembler instead, and the first file will fail with "
                        "something like \"invalid -march= option\". The compiler and its binutils have "
                        "to come from the same package set. breeze/scripts/setup.sh checks this with a test "
                        "compile and, on Arch for 32-bit ARM, installs a matching set (see "
                        "\"32-bit ARM on Arch\" in the README). Elsewhere install the binutils that "
                        "belong to this compiler.")
                endif()
            endif()
        else()
            # Clang itself is multi-target and happily emits object code for
            # ${_pmn_tc_triplet} with no cross package installed at all --
            # the failure this check guards against only shows up much
            # later, and far more cryptically, at the LINK step: Clang
            # still hands linking to whatever plain `ld` it finds (the
            # host's own, unless told otherwise), which doesn't recognize
            # the target's ELF flavor ("unrecognised emulation mode:
            # armelf_linux_eabi", say) since it was never built with that
            # target enabled. The GCC branch above never has this problem
            # -- "${_pmn_tc_triplet}-g++" simply doesn't exist without the
            # cross package, so pmn_use_compilers already fails clearly --
            # so checking for that same binary here (found above, for the
            # sysroot query), even though Clang doesn't need it to
            # compile, catches the same missing-package case before it
            # reaches a linker error with no obvious connection to the
            # real cause.
            if(NOT _pmn_tc_cross_gxx)
                message(FATAL_ERROR
                    "The '${PMN_TOOLCHAIN_DIST_TARGET}' toolchain needs the ${_pmn_tc_triplet} cross "
                    "package (for its linker and the target's libstdc++/libc) even to use Clang, and "
                    "it isn't on PATH: run breeze/scripts/setup.sh to install it for your package manager "
                    "(apt for every target; dnf for AArch64 and 32-bit ARM, from a COPR; pacman for "
                    "AArch64, and for 32-bit ARM from the AUR, which breeze/scripts/setup.sh offers -- "
                    "see its own \"why\" text for details), or by hand -- e.g. on Debian/Ubuntu: "
                    "sudo apt install ${_pmn_tc_gcc_pkg}\n"
                    "(Without it, configuring would proceed but linking would fail with an obscure "
                    "\"unrecognised emulation mode\" or similar error instead of this one.)")
            endif()
            pmn_use_compilers(clang++ clang
                "Run breeze/scripts/setup.sh to install Clang plus the matching cross package, or by hand -- e.g. on Debian/Ubuntu: sudo apt install clang ${_pmn_tc_gcc_pkg} (the second package provides the target's libraries)")
            set(_pmn_tc_clang_triple "${_pmn_tc_triplet}")
            if(_pmn_tc_cross_machine MATCHES "^${_pmn_tc_processor}")
                set(_pmn_tc_clang_triple "${_pmn_tc_cross_machine}")
            endif()
            if(NOT _pmn_tc_clang_triple STREQUAL _pmn_tc_triplet)
                message(STATUS "Clang targets ${_pmn_tc_clang_triple}, the triple ${_pmn_tc_cross_gxx} was built for (the preset's default is ${_pmn_tc_triplet})")
            endif()
            set(CMAKE_CXX_COMPILER_TARGET "${_pmn_tc_clang_triple}")
            set(CMAKE_C_COMPILER_TARGET   "${_pmn_tc_clang_triple}")

            # Unlike GCC, Clang has no distro-specific packaging knowledge
            # baked in, so it falls back to a generic guess for where
            # THIS triplet's crt1.o/crtbegin.o/libgcc live -- one that
            # happens to match a flat /usr/<triplet> layout (apt's,
            # pacman's) but not one nested under its own sys-root (dnf's
            # COPR toolchain). Guessed wrong, it silently resolves to the
            # HOST's own crt1.o instead -- still a real file, just the
            # wrong architecture, which surfaces as an obscure linker
            # error ("Relocations in generic ELF", confirmed on a Fedora
            # aarch64 build) with no obvious connection to a missing
            # flag. The real sysroot queried above, from the cross-gcc
            # that's actually installed rather than guessed at here,
            # fixes this the same way for either family; only Clang needs
            # telling. --gcc-toolchain additionally points Clang at
            # crtbegin.o/libgcc, which a sysroot alone doesn't cover on
            # every layout (confirmed necessary for this same class of
            # problem on Arch by the Linux kernel's own cross-build
            # tooling, tools/scripts/Makefile.include -- included here
            # only alongside a real sysroot, for the same "don't touch
            # what Clang already gets right" reason); /usr is where a
            # package manager's own cross-gcc lives on every platform
            # this toolchain supports.
            if(_pmn_tc_cross_sysroot)
                set(CMAKE_SYSROOT "${_pmn_tc_cross_sysroot}")
                # Appended only if absent: this file is read again for the
                # same scope (project() and each enabled language, not just
                # try_compile), and a plain append put the flag twice on every
                # compile line and four times on every link line.
                foreach(_pmn_tc_flags_var CMAKE_CXX_FLAGS_INIT CMAKE_C_FLAGS_INIT
                        CMAKE_EXE_LINKER_FLAGS_INIT CMAKE_SHARED_LINKER_FLAGS_INIT)
                    if(NOT "${${_pmn_tc_flags_var}}" MATCHES "--gcc-toolchain=/usr")
                        string(APPEND ${_pmn_tc_flags_var} " --gcc-toolchain=/usr")
                    endif()
                endforeach()
            endif()
        endif()
        pmn_cross_emulator("${_pmn_tc_qemu}" -L "${_pmn_tc_emulator_root}")
    endif()
endmacro()

# -----------------------------------------------------------------------
# pmn_mingw_toolchain(<x64|x86>)
#
# Behind windows-x64-mingw64 and windows-x86-mingw32. On a Windows host
# (an MSYS2 MINGW64/MINGW32 shell, or a standalone MinGW-w64) this only
# picks the compiler by its triplet-prefixed name. On a Linux host it is a
# real cross build using the distro's own mingw-w64 packages -- apt, dnf
# and pacman all ship a working one (breeze/scripts/setup.sh knows each; pacman's
# single mingw-w64-gcc covers both x64 and x86, unlike apt/dnf's separate
# packages per architecture) -- with wine as the emulator if installed.
# -----------------------------------------------------------------------
macro(pmn_mingw_toolchain _pmn_tc_arch)
    if("${_pmn_tc_arch}" STREQUAL "x64")
        set(_pmn_tc_processor "x86_64")
        set(_pmn_tc_triplet   "x86_64-w64-mingw32")
        set(_pmn_tc_pkg       "g++-mingw-w64-x86-64")
    elseif("${_pmn_tc_arch}" STREQUAL "x86")
        set(_pmn_tc_processor "i686")
        set(_pmn_tc_triplet   "i686-w64-mingw32")
        set(_pmn_tc_pkg       "g++-mingw-w64-i686")
    else()
        message(FATAL_ERROR "pmn_mingw_toolchain: unknown architecture '${_pmn_tc_arch}'")
    endif()

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        pmn_use_compilers("${_pmn_tc_triplet}-g++" "${_pmn_tc_triplet}-gcc"
            "Install MinGW-w64 (e.g. MSYS2's mingw-w64 packages) and put its bin directory on PATH. breeze\\scripts\\build.bat puts MSYS2's folder on PATH by itself.")
    else()
        pmn_cross_target(Windows "${_pmn_tc_processor}" "/usr/${_pmn_tc_triplet}")
        pmn_use_compilers("${_pmn_tc_triplet}-g++" "${_pmn_tc_triplet}-gcc"
            "Run breeze/scripts/setup.sh to install the MinGW-w64 cross compiler for your package manager, or by hand -- e.g. on Debian/Ubuntu: sudo apt install ${_pmn_tc_pkg}")
        # Tried architecture-matched name first, the other as fallback --
        # not just for distros that ship only one of the two (the
        # original reason for trying both), but because on at least one
        # that ships both, plain "wine" turned out not to actually be
        # 64-bit capable: windows-x64-mingw64 failed to start at all
        # through it ("Bad EXE format") while windows-x86-mingw32 through
        # that same "wine" worked fine, and explicitly preferring
        # "wine64" for the x64 build fixed it. Confirmed harmless where
        # this was never a problem (Arch, Fedora): wine64 there either
        # already matches or doesn't exist, so the fallback is what runs
        # either way, unchanged from before.
        if("${_pmn_tc_arch}" STREQUAL "x64")
            pmn_cross_emulator("wine64;wine")
        else()
            pmn_cross_emulator("wine;wine64")
        endif()
    endif()
endmacro()

# -----------------------------------------------------------------------
# pmn_msvc_toolchain(<x64|arm64>)
#
# Behind windows-x64-msvc and windows-arm64-msvc. cl.exe has no --target:
# which architecture it produces is decided by WHICH cl.exe comes first on
# PATH, i.e. by the Visual Studio developer environment the shell was
# started from. A toolchain file therefore can't switch architectures for
# MSVC. What it can do is pick cl instead of letting CMake fall through to
# whatever other compiler is on PATH, and fail early with the instruction
# that fixes the usual cause. Whether the cl.exe it found really targets
# the architecture in the DIST_TARGET is then verified by
# TargetSelection.cmake, from CMAKE_CXX_COMPILER_ARCHITECTURE_ID.
# -----------------------------------------------------------------------
macro(pmn_msvc_toolchain _pmn_tc_arch)
    if("${_pmn_tc_arch}" STREQUAL "x64")
        pmn_use_compilers(cl cl
            "Open an \"x64 Native Tools Command Prompt for VS\" (or a Developer PowerShell for VS defaulted to x64) and run this again. Or build with breeze\\scripts\\build.bat --preset ${PMN_TOOLCHAIN_DIST_TARGET}, which enters that environment for you.")
    else()
        pmn_use_compilers(cl cl
            "Open a Visual Studio developer prompt configured for ARM64 -- an \"ARM64 Native Tools Command Prompt for VS\", or on an x64 machine an \"x64_arm64 Cross Tools Command Prompt for VS\" (vcvarsall.bat x64_arm64) -- and run this again. Or build with breeze\\scripts\\build.bat --preset ${PMN_TOOLCHAIN_DIST_TARGET}, which enters that environment for you.")
    endif()
    pmn_check_msvc_target("${_pmn_tc_arch}")
endmacro()

# -----------------------------------------------------------------------
# pmn_clang_cl_toolchain(<x64|arm64>)
#
# Behind windows-x64-clang-cl and windows-arm64-clang-cl: LLVM's clang-cl,
# the cl.exe-compatible driver, targeting the MSVC ABI. Unlike cl.exe,
# clang-cl takes --target, so the architecture is pinned here
# (CMAKE_CXX_COMPILER_TARGET -> --target=<triple> on every compile and
# link line, and while CMake identifies the compiler) instead of depending
# on whatever the environment or the machine's own architecture defaults
# to. That is what lets windows-x64-clang-cl mean x64 on an ARM64 Windows
# machine too.
#
# The MSVC STL headers and the Windows SDK libraries still come from a
# Visual Studio / Build Tools install, as they do for any clang-cl build.
# -----------------------------------------------------------------------
macro(pmn_clang_cl_toolchain _pmn_tc_arch)
    if("${_pmn_tc_arch}" STREQUAL "x64")
        set(_pmn_tc_triple "x86_64-pc-windows-msvc")
    elseif("${_pmn_tc_arch}" STREQUAL "arm64")
        set(_pmn_tc_triple "aarch64-pc-windows-msvc")
    else()
        message(FATAL_ERROR "pmn_clang_cl_toolchain: unknown architecture '${_pmn_tc_arch}'")
    endif()
    pmn_use_compilers(clang-cl clang-cl
        "Install LLVM (e.g.:  winget install LLVM.LLVM) or Visual Studio's \"C++ Clang tools for Windows\" component, and make sure clang-cl's directory is on PATH. breeze\\scripts\\build.bat finds LLVM's and Visual Studio's copies by itself.")
    set(CMAKE_CXX_COMPILER_TARGET "${_pmn_tc_triple}")
    set(CMAKE_C_COMPILER_TARGET   "${_pmn_tc_triple}")
    pmn_check_msvc_target("${_pmn_tc_arch}")
endmacro()

# -----------------------------------------------------------------------
# pmn_msys_clang_toolchain()
#
# Behind windows-x64-clang and windows-arm64-clang: Clang with its own
# GNU-style driver (clang++), as in an MSYS2 CLANG64 / CLANGARM64 shell
# -- distinct from clang-cl. Which architecture that clang++ targets is
# the shell environment's default, so nothing is pinned here; the
# environment is what makes clang++ a mingw-ABI compiler for the right
# machine.
# -----------------------------------------------------------------------
macro(pmn_msys_clang_toolchain)
    pmn_use_compilers(clang++ clang
        "Open an MSYS2 CLANG64 (x64) or CLANGARM64 (ARM64) shell, whose clang++ targets the matching mingw ABI by default. breeze\\scripts\\build.bat puts that shell's toolchain folder on PATH for you.")
endmacro()

# -----------------------------------------------------------------------
# pmn_macos_toolchain(<arm64|x64>)
#
# Behind macos-arm64-clang and macos-x64-clang. Apple's clang is ONE
# multi-architecture compiler: which architecture it emits is a flag
# (-arch), not a different program. So unlike the Linux cross builds there
# is no cross compiler to find, no sysroot to restrict lookups to and no
# emulator to register (an x86_64 binary runs on an Apple Silicon Mac
# through Rosetta 2, and try_run works as usual) -- and CMAKE_CROSSCOMPILING
# correctly stays FALSE. What this pins instead:
#
#   CMAKE_OSX_ARCHITECTURES      the ONE architecture, always -- even when
#       it is the machine's own. That is the only reliable statement of what
#       gets built: without it the compiler follows the process that
#       launched it, so a cmake running under Rosetta 2 on an Apple Silicon
#       Mac would quietly produce x86_64 for a target that says arm64.
#   CMAKE_OSX_DEPLOYMENT_TARGET  the oldest macOS the result runs on:
#       11.0, the first release that runs on Apple Silicon. Left unset it
#       defaults to the SDK's own version, and everything built then
#       refuses to start on any macOS older than the build machine's.
#
# Both only take effect if set BEFORE the first project(), which is
# exactly when a toolchain file runs, and both yield to an explicit
# -DCMAKE_OSX_...= on the command line (the label check in
# TargetSelection.cmake then catches an architecture that no longer matches
# the target). Homebrew's LLVM clang instead of Apple's works the same
# way: -DCMAKE_CXX_COMPILER=$(brew --prefix llvm)/bin/clang++.
# -----------------------------------------------------------------------
macro(pmn_macos_toolchain _pmn_tc_arch)
    if("${_pmn_tc_arch}" STREQUAL "arm64")
        set(_pmn_tc_osx_arch "arm64")
    elseif("${_pmn_tc_arch}" STREQUAL "x64")
        set(_pmn_tc_osx_arch "x86_64")
    else()
        message(FATAL_ERROR "pmn_macos_toolchain: unknown architecture '${_pmn_tc_arch}'")
    endif()

    if(NOT CMAKE_OSX_ARCHITECTURES)
        set(CMAKE_OSX_ARCHITECTURES "${_pmn_tc_osx_arch}")
    endif()
    if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
        set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
    endif()

    # /usr/bin/clang++ exists on every Mac, as a stub that only works once
    # the Command Line Tools (or Xcode) are installed -- without them CMake
    # would fail inside its own compiler check with "xcrun: error: invalid
    # active developer path". Say what's actually wrong instead.
    if(CMAKE_HOST_APPLE)
        execute_process(COMMAND xcode-select -p
            RESULT_VARIABLE _pmn_tc_xcode_rc
            OUTPUT_QUIET ERROR_QUIET)
        if(NOT _pmn_tc_xcode_rc EQUAL 0)
            message(FATAL_ERROR
                "The '${PMN_TOOLCHAIN_DIST_TARGET}' toolchain needs Apple's compiler, but no "
                "developer directory is set (xcode-select -p failed).\n"
                "Install the Xcode Command Line Tools:  xcode-select --install\n"
                "(breeze/scripts/setup.sh offers to do this for you.)")
        endif()
    endif()

    pmn_use_compilers(clang++ clang
        "Install the Xcode Command Line Tools:  xcode-select --install")
endmacro()
