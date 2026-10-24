# =============================================================================
# HostArch.cmake
#
# One place to turn this project's own architecture labels -- x64, arm64,
# or arm32 (empty if unrecognized) -- out of a processor string. Two entry
# points, because "which architecture" has two different questions behind it:
#
#   pmn_host_arch()     the machine CMake is actually running ON.
#                        NinjaPin.cmake / DoxygenPin.cmake use it to decide
#                        whether a pinned-tool download exists for the machine
#                        running CMake -- always a HOST question, independent
#                        of what's being built. TargetSelection.cmake also uses
#                        it for Clang's GNU-style driver on Windows (see
#                        below for why MSVC/clang-cl need a different check,
#                        done separately in that file).
#
#   pmn_target_arch()   the machine the build is FOR, i.e.
#                        CMAKE_SYSTEM_PROCESSOR. TargetSelection.cmake's Linux
#                        DIST_TARGET detection uses it. On a native build it
#                        is the same answer as pmn_host_arch() (CMake sets
#                        CMAKE_SYSTEM_PROCESSOR from the host unless told
#                        otherwise); the difference is a cross build, where a
#                        toolchain file (breeze/cmake/toolchains/) sets it to the
#                        target -- asking the host there would label an
#                        aarch64 cross build "x64".
#
# Both share one aarch64/armv7l/... spelling list, and the platform-specific
# unreliability below is only handled once. Needs no project()/compiler
# detection, so it's safe to include from a bare `cmake -P` script.
#
# About pmn_host_arch() on each platform: on Linux it is
# CMAKE_HOST_SYSTEM_PROCESSOR, which is just `uname -m` -- reliable, with
# one catch that used to break the pinned-tool download on every Linux
# machine: `cmake -P` (script mode -- how breeze/scripts/setup.sh runs
# FetchNinja.cmake and FetchDoxygen.cmake) never runs CMake's system
# detection, so CMAKE_HOST_SYSTEM_PROCESSOR is simply not defined there.
# In that case this asks the OS itself, with `uname -m`. On macOS it is
# the same `uname -m`, corrected for Rosetta 2 (see the comment inside the
# function). On
# Windows it deliberately does NOT use CMAKE_HOST_SYSTEM_
# PROCESSOR (or CMAKE_SYSTEM_PROCESSOR): both are just the
# PROCESSOR_ARCHITECTURE environment variable, which reports the
# architecture of the CURRENT PROCESS, not the machine -- a 32-bit
# cmake.exe (still a completely ordinary, common download; nothing exotic)
# running under WoW64 on an ordinary 64-bit machine reports "x86" here even
# though the machine itself is x64 or ARM64. That's the same class of
# problem as the MSVC/clang-cl architecture-detection trap in
# TargetSelection.cmake (CMake issue #25466: gitlab.kitware.com/cmake/cmake/-/issues/25466),
# just via WoW64 process redirection rather than a cross-targeting
# compiler -- confirmed the hard way, as exactly what broke the pinned-
# ninja/-doxygen lookup below on an entirely ordinary 64-bit machine with a
# 32-bit cmake.exe on PATH. PROCESSOR_ARCHITEW6432 is what Windows itself
# sets to expose the TRUE architecture to a WoW64-redirected 32-bit
# process; it's simply unset outside WoW64, which is exactly when
# PROCESSOR_ARCHITECTURE was already correct anyway -- so preferring it
# when present, falling back to PROCESSOR_ARCHITECTURE otherwise, is
# correct either way.
# =============================================================================

include_guard(GLOBAL)

# _pmn_arch_label(<processor-string> <out-var>)
#
# The one place the aarch64/x86_64/armv7l/... spellings are mapped to this
# project's x64/arm64/arm32 labels. <out-var> gets one of those, or "" if
# unrecognized.
function(_pmn_arch_label PROCESSOR OUT_VAR)
    if(PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set(${OUT_VAR} "arm64" PARENT_SCOPE)
    elseif(PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(${OUT_VAR} "x64" PARENT_SCOPE)
    elseif(PROCESSOR MATCHES "^[Aa][Rr][Mm]")
        # Every other spelling of 32-bit ARM this project has seen: armv6l
        # (Raspberry Pi 1/Zero), armv7l (the common case -- Raspberry Pi
        # 2/3/4 32-bit OS, generic armhf), armv8l (a 32-bit personality/
        # chroot on 64-bit ARM hardware), or bare "arm"/"ARM". Checked
        # after arm64/aarch64 above since those also start with "arm".
        set(${OUT_VAR} "arm32" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "" PARENT_SCOPE)
    endif()
endfunction()

# pmn_host_arch(<out-var> [<raw-out-var>])
#
# <out-var> gets one of x64/arm64/arm32/"" (unrecognized) for the machine
# running CMake. The optional <raw-out-var> gets whatever raw string was
# actually checked to produce that -- callers building an error message for
# the "" case should use this rather than assuming which underlying
# variable/environment variable was consulted, since that differs by
# platform (see above).
function(pmn_host_arch OUT_VAR)
    if(CMAKE_HOST_WIN32)
        if(NOT "$ENV{PROCESSOR_ARCHITEW6432}" STREQUAL "")
            set(_pmn_ha_processor "$ENV{PROCESSOR_ARCHITEW6432}")
        else()
            set(_pmn_ha_processor "$ENV{PROCESSOR_ARCHITECTURE}")
        endif()
    elseif(CMAKE_HOST_SYSTEM_PROCESSOR)
        set(_pmn_ha_processor "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    elseif(CMAKE_HOST_UNIX)
        # Script mode (cmake -P): not defined -- see the header. This is
        # exactly what CMake itself does to fill it in during a configure.
        execute_process(COMMAND uname -m
            OUTPUT_VARIABLE _pmn_ha_processor
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
    else()
        set(_pmn_ha_processor "${CMAKE_SYSTEM_PROCESSOR}")
    endif()

    # macOS: a process running under Rosetta 2 -- an x86_64 cmake on an Apple
    # Silicon Mac, entirely ordinary since Intel builds of CMake and of most
    # developer tools still circulate -- is told it's on an x86_64 machine,
    # by `uname -m` and so by CMAKE_HOST_SYSTEM_PROCESSOR alike. The same
    # class of trap as a 32-bit process under WoW64 on Windows (see the
    # header), and fixed the same way: ask about the MACHINE.
    # hw.optional.arm64 is 1 on any Apple Silicon Mac no matter whether the
    # asking process is translated, and doesn't exist on Intel (-i makes a
    # missing OID a silent empty answer instead of an error).
    if(CMAKE_HOST_APPLE)
        _pmn_arch_label("${_pmn_ha_processor}" _pmn_ha_probe)
        if(_pmn_ha_probe STREQUAL "x64")
            execute_process(COMMAND sysctl -in hw.optional.arm64
                OUTPUT_VARIABLE _pmn_ha_arm64
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET)
            if(_pmn_ha_arm64 STREQUAL "1")
                set(_pmn_ha_processor "arm64")
            endif()
        endif()
    endif()

    if(ARGC GREATER 1)
        set(${ARGV1} "${_pmn_ha_processor}" PARENT_SCOPE)
    endif()

    _pmn_arch_label("${_pmn_ha_processor}" _pmn_ha_label)
    set(${OUT_VAR} "${_pmn_ha_label}" PARENT_SCOPE)
endfunction()

# pmn_target_arch(<out-var> [<raw-out-var>])
#
# Same contract as pmn_host_arch(), but for the machine the build is FOR:
# CMAKE_SYSTEM_PROCESSOR. Only meaningful where that variable can be
# trusted -- Linux, where it is `uname -m` for a native build and whatever
# the toolchain file says for a cross build. Not for MSVC/clang-cl, where
# it reflects the cmake.exe process instead (see the header).
function(pmn_target_arch OUT_VAR)
    if(ARGC GREATER 1)
        set(${ARGV1} "${CMAKE_SYSTEM_PROCESSOR}" PARENT_SCOPE)
    endif()
    _pmn_arch_label("${CMAKE_SYSTEM_PROCESSOR}" _pmn_ta_label)
    set(${OUT_VAR} "${_pmn_ta_label}" PARENT_SCOPE)
endfunction()
