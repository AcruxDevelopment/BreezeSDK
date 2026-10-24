#!/usr/bin/env bash
# Run an executable module by its CMake target name (as registered in
# that module's own CMakeLists.txt), resolved via the manifest that
# _write_module_manifest() generates at configure time -- so this script
# never needs updating when modules are added, removed, or renamed.
#
# Usage (from the project root):
#   breeze/scripts/run.sh [--preset <name>] <target-name> [-- program-args...]
#
#   --preset <name>  Run the build made with that preset (out/build/<name>).
#                    Without it: the build breeze/scripts/build.sh made last, or
#                    the only one that exists. Must come first if given at
#                    all; --preset=<name> also works.
#
# Examples:
#   breeze/scripts/run.sh hello_exe
#   breeze/scripts/run.sh --preset linux-x64-clang hello_exe
#   breeze/scripts/run.sh farewell_exe -- Ale
#
# Set BUILD_DIR to run out of an exact build directory instead.
#
# An executable built for another architecture or OS -- linux-arm64-* on an
# x64 machine, windows-*-mingw* from Linux -- is run under the emulator its
# toolchain registered (qemu-user, wine) if one was installed when the build
# was configured; otherwise it can only run on the target itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

# _pmn_read_config, _pmn_resolve_build_dir, _pmn_record_build_dir.
source "$SCRIPT_DIR/_common.sh"

# --preset must come first if given at all, same as breeze/scripts/build.sh.
PRESET=""
case "${1:-}" in
    --preset)
        if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
            echo "error: --preset requires a value, e.g. --preset linux-x64-gcc" >&2
            exit 1
        fi
        PRESET="$2"
        shift 2
        ;;
    --preset=*)
        PRESET="${1#--preset=}"
        shift
        if [ -z "$PRESET" ]; then
            echo "error: --preset= requires a value, e.g. --preset=linux-x64-gcc" >&2
            exit 1
        fi
        ;;
esac

# BUILD_DIR from the environment beats everything; otherwise --preset, else
# whichever build was made last (see breeze/cmake/BuildDir.cmake). Help and the
# usage message look it up best-effort -- they should still print on a
# fresh checkout with nothing built yet -- while actually running
# something needs a real answer, and stops with the reason if there isn't
# one.
_pmn_try_build_dir() {
    if [ -z "${BUILD_DIR:-}" ]; then
        BUILD_DIR="$(_pmn_resolve_build_dir "$PRESET" 2>/dev/null || true)"
    fi
}

list_targets() {
    local manifest
    [ -n "${BUILD_DIR:-}" ] || return 0
    for manifest in "${BUILD_DIR}"/module_manifest-*.txt; do
        [ -e "$manifest" ] || continue
        cut -d= -f1 "$manifest"
    done | sort -u
}

usage() {
    _pmn_try_build_dir
    echo "Usage: $0 [--preset <name>] <cmake-target-name> [-- program-args...]" >&2
    echo >&2
    echo "Available executable targets:" >&2
    local targets
    targets="$(list_targets)"
    if [ -n "$targets" ]; then
        echo "$targets" | sed 's/^/  /' >&2
    else
        echo "  (none found -- did you run breeze/scripts/build.sh?)" >&2
    fi
    exit 1
}

show_help() {
    _pmn_try_build_dir
    echo "Usage: $0 [--preset <name>] <cmake-target-name> [-- program-args...]"
    echo
    echo "Runs an executable module by its CMake target name, resolved via the"
    echo "manifest breeze/scripts/build.sh generates at configure time -- see the"
    echo "comment at the top of this script."
    echo
    echo "  --preset <name>  Run the build made with that preset. Default: the"
    echo "                   build breeze/scripts/build.sh made last."
    echo
    echo "Available executable targets:"
    local targets
    targets="$(list_targets)"
    if [ -n "$targets" ]; then
        echo "$targets" | sed 's/^/  /'
    else
        echo "  (none found -- did you run breeze/scripts/build.sh?)"
    fi
    echo
    echo "Examples:"
    echo "  breeze/scripts/run.sh hello_exe"
    echo "  breeze/scripts/run.sh --preset linux-x64-clang hello_exe"
    echo "  breeze/scripts/run.sh farewell_exe -- Ale"
    exit 0
}

case "${1:-}" in
    -h|--help) show_help ;;
esac

[ $# -ge 1 ] || usage

TARGET_NAME="$1"
shift
if [ "${1:-}" = "--" ]; then
    shift
fi

if [ -z "${BUILD_DIR:-}" ]; then
    # Explains itself and stops if there's nothing to pick.
    BUILD_DIR="$(_pmn_resolve_build_dir "$PRESET")"
fi

MANIFEST=""
for m in "${BUILD_DIR}"/module_manifest-*.txt; do
    [ -e "$m" ] || continue
    MANIFEST="$m"
    break
done

if [ -z "$MANIFEST" ]; then
    echo "error: no build manifest found in '${BUILD_DIR}'. Run breeze/scripts/build.sh${PRESET:+ --preset $PRESET} first." >&2
    exit 1
fi

BIN_PATH="$(grep "^${TARGET_NAME}=" "$MANIFEST" | head -n1 | cut -d= -f2- || true)"

if [ -z "$BIN_PATH" ]; then
    echo "error: no executable target named '${TARGET_NAME}' in '${BUILD_DIR}'." >&2
    echo "Available targets:" >&2
    list_targets | sed 's/^/  /' >&2
    exit 1
fi

if [ ! -x "$BIN_PATH" ]; then
    echo "error: '${BIN_PATH}' was not found or is not executable. Rebuild with breeze/scripts/build.sh${PRESET:+ --preset $PRESET}." >&2
    exit 1
fi

# _pmn_pe_kind <file>: what kind of Windows program this is, read from the
# Machine field of its PE header -- the two bytes after the "PE\0\0"
# signature, which e_lfanew (the 4 bytes at offset 0x3C) points at. Prints
# x86 (32-bit), x64 (64-bit x86), or other (ARM64, a file that isn't a PE at
# all, one that can't be read). `od` rather than `file`, so nothing has to be
# installed, and byte by byte so the host's endianness doesn't matter.
_pmn_pe_kind() {
    local o0 o1 o2 o3 s0 s1 s2 s3 m0 m1 off
    read -r o0 o1 o2 o3 <<< "$(od -An -tu1 -j60 -N4 "$1" 2>/dev/null || true)"
    if [ -z "${o3:-}" ]; then
        echo other
        return 0
    fi
    off=$(( o0 + o1 * 256 + o2 * 65536 + o3 * 16777216 ))
    read -r s0 s1 s2 s3 m0 m1 <<< "$(od -An -tu1 -j"$off" -N6 "$1" 2>/dev/null || true)"
    # 80 69 0 0 is "PE\0\0".
    if [ "${s0:-}" = 80 ] && [ "${s1:-}" = 69 ] && [ "${s2:-}" = 0 ] && [ "${s3:-}" = 0 ] && [ -n "${m1:-}" ]; then
        case $(( m0 + m1 * 256 )) in
            332)   echo x86; return 0 ;;    # 0x014c  IMAGE_FILE_MACHINE_I386
            34404) echo x64; return 0 ;;    # 0x8664  IMAGE_FILE_MACHINE_AMD64
        esac
    fi
    echo other
}

# _pmn_wine_lacks_wine64 <wine>: 0 if <wine> is Debian/Ubuntu's helper script
# and this machine has that packaging's 32-bit loader but no 64-bit one -- the
# state described below -- so that a 64-bit program cannot run here whatever
# else is tried. Recognised by layout rather than by which version of wine it
# is: a script under /usr/bin (alternatives -> wine-stable or
# wine-development) beside a loader directory that holds wine but no wine64.
_pmn_wine_lacks_wine64() {
    local emu real dir
    emu="$(command -v "$1" 2>/dev/null)" || return 1
    real="$(readlink -f "$emu" 2>/dev/null)" || real="$emu"
    case "$real" in
        /usr/bin/wine-development) dir=/usr/lib/wine-development ;;
        /usr/bin/*)                dir=/usr/lib/wine ;;
        *)                         return 1 ;;
    esac
    [ "$(head -c2 "$real" 2>/dev/null)" = '#!' ] && [ -x "$dir/wine" ] && [ ! -x "$dir/wine64" ]
}

# _pmn_wine64_loader <wine>: prints a loader that can run 64-bit Windows
# programs and create a 64-bit prefix for them, given the plain `wine` the
# toolchain registered -- or fails if it knows of nothing better than <wine>.
#
# Plain `wine` isn't always that. On Debian and Ubuntu it is a helper script
# (alternatives -> wine-stable / wine-development), not a loader, and the one
# in wine 9.0's packaging runs the 32-bit loader whenever wine32 is installed
# -- which breeze/scripts/setup.sh makes sure of, for the 32-bit preset. A 32-bit
# loader with no wine64 to hand over to creates a 32-bit prefix even under
# WINEARCH=win64 and then refuses it: "WINEARCH set to win64 but '<prefix>'
# is a 32-bit installation". That is what a machine looks like after
# `apt-get install wine wine32:i386` (wine only depends on "wine64 | wine32",
# so wine64 gets left out): reproduced, with that exact output, from that
# command. The 64-bit loader is a separate file there, /usr/lib/wine/wine64,
# and nothing puts it on PATH.
_pmn_wine64_loader() {
    local emu real w64
    emu="$(command -v "$1" 2>/dev/null)" || return 1
    real="$(readlink -f "$emu" 2>/dev/null)" || real="$emu"
    # A wine64 right next to it: Arch, Fedora, WineHQ's /opt/wine-*/bin, ...
    for w64 in "${real%/*}/wine64" "${emu%/*}/wine64"; do
        if [ -x "$w64" ]; then
            printf '%s\n' "$w64"
            return 0
        fi
    done
    case "${real##*/}" in
        wine-stable)      w64=/usr/lib/wine/wine64 ;;
        wine-development) w64=/usr/lib/wine-development/wine64 ;;
        *)                return 1 ;;
    esac
    if [ -x "$w64" ]; then
        printf '%s\n' "$w64"
        return 0
    fi
    return 1
}

# A cross build's toolchain file (breeze/cmake/toolchains/) registers an emulator --
# qemu-user for another CPU, wine for Windows -- as
# CMAKE_CROSSCOMPILING_EMULATOR when one is installed, which is also what
# lets ctest run the same binaries. Use it the same way. It's a
# ";"-separated list (the emulator, then its arguments).
RUN_PREFIX=()
if [ -f "${BUILD_DIR}/CMakeCache.txt" ]; then
    _pmn_emulator="$(sed -n 's/^CMAKE_CROSSCOMPILING_EMULATOR:[A-Z]*=//p' "${BUILD_DIR}/CMakeCache.txt")"
    if [ -n "$_pmn_emulator" ]; then
        IFS=';' read -r -a RUN_PREFIX <<< "$_pmn_emulator"
    fi
fi

# Wine refuses to start at all without a valid XDG_RUNTIME_DIR -- "error:
# XDG_RUNTIME_DIR is invalid or not set in the environment" -- even for a
# console-only .exe that needs no desktop integration whatsoever; a
# session manager normally sets this, which containers (confirmed on a
# distrobox one) typically have no reason to run. Wine only checks that
# the directory exists with the right ownership/permissions, not that it
# came from a real session, so a private one under TMPDIR is enough to
# get past this. Only for wine, and only if nothing is already set -- a
# real desktop session already has a real one, left alone.
case "${RUN_PREFIX[0]:-}" in
    */wine|wine|*/wine64|wine64)
        if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
            export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/xdg-runtime-$(id -u)"
            mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
            chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null
        fi

        # 32-bit or 64-bit, read from the program itself. Everything below
        # keeps the two apart, because a wine prefix is one or the other from
        # the moment it is created and is never shared safely between them.
        _pmn_kind="$(_pmn_pe_kind "$BIN_PATH")"

        # A 64-bit program needs a loader that can build and run a 64-bit
        # prefix, which plain `wine` isn't everywhere (see
        # _pmn_wine64_loader).
        if [ "$_pmn_kind" = x64 ] && [ "${RUN_PREFIX[0]##*/}" = wine ]; then
            if _pmn_w64="$(_pmn_wine64_loader "${RUN_PREFIX[0]}")"; then
                RUN_PREFIX[0]="$_pmn_w64"
            elif _pmn_wine_lacks_wine64 "${RUN_PREFIX[0]}"; then
                # Nothing below can make this work, and trying only ends in
                # wine's own "WINEARCH set to win64 but ... is a 32-bit
                # installation" -- which says nothing about the cause.
                echo "error: ${TARGET_NAME} is a 64-bit Windows program, but this machine has only the" >&2
                echo "       32-bit wine, which can neither run it nor create the 64-bit prefix it" >&2
                echo "       needs. Debian and Ubuntu package the 64-bit part separately:" >&2
                echo "           sudo apt install wine64        (breeze/scripts/setup.sh installs it too)" >&2
                exit 1
            fi
        fi
        # Running Debian's own loader directly -- chosen just above, or
        # already what the build registered -- means going around the helper
        # script that normally runs it, so do the two things that script does
        # for wine64: point WINELOADER at it, and quiet wine's "fixme:"
        # chatter with WINEDEBUG=fixme-all. Each only if nothing set it.
        case "${RUN_PREFIX[0]}" in
            /usr/lib/wine/wine64|/usr/lib/wine-development/wine64)
                if [ -z "${WINELOADER:-}" ]; then export WINELOADER="${RUN_PREFIX[0]}"; fi
                if [ -z "${WINEDEBUG:-}" ]; then export WINEDEBUG=fixme-all; fi
                ;;
        esac

        # Default wine prefix is ~/.wine, shared with every other use of
        # wine on the machine -- scoping it under .cache/ instead makes a
        # fresh `rm -rf .cache/wine` the fix for anything that looks like a
        # wine problem rather than a build one, and keeps this project's
        # own wine state from mixing with anything else's. One prefix per
        # kind of program (.cache/wine/x86, .cache/wine/x64): a prefix's
        # architecture is fixed by whichever program first creates it, so
        # sharing one made the outcome depend on which preset happened to
        # run first, and on a wine whose 32-bit loader can only make 32-bit
        # prefixes, no amount of recreating it helped. Only if WINEPREFIX
        # isn't already set -- someone who's deliberately pointed it
        # elsewhere gets left alone, and that includes never deleting it.
        if [ -z "${WINEPREFIX:-}" ]; then
            # Older versions used .cache/wine itself as the one prefix. A
            # prefix has a system.reg at its top, so that is easy to tell
            # apart from this layout; its content is only a disposable cache.
            if [ -f "$PWD/.cache/wine/system.reg" ]; then
                rm -rf "$PWD/.cache/wine"
            fi
            export WINEPREFIX="$PWD/.cache/wine/$_pmn_kind"
            # A 64-bit prefix recorded as 32-bit (a prefix's own system.reg
            # says which, in a line reading exactly "#arch=win32" or
            # "#arch=win64") can't be what asked for 64-bit, and wine refuses
            # to run anything against it once WINEARCH=win64 disagrees --
            # so it's rebuilt, since it's this project's own cache.
            if [ "$_pmn_kind" = x64 ] && [ -f "$WINEPREFIX/system.reg" ] \
                && grep -q '^#arch=win32' "$WINEPREFIX/system.reg" 2>/dev/null; then
                rm -rf "$WINEPREFIX"
            fi
        fi
        # Wine creates the last component of the prefix path and no more, so
        # with no .cache/ yet (a fresh checkout) it fails: "wine: chdir to
        # <prefix> : No such file or directory".
        mkdir -p "$WINEPREFIX"

        # A 64-bit prefix is asked for outright, so that one that can't be
        # made fails at once and by name rather than as a 32-bit prefix that
        # then can't run the program. Left alone for 32-bit programs: any
        # prefix runs those, and forcing win32 isn't possible on every wine.
        if [ "$_pmn_kind" = x64 ] && [ -z "${WINEARCH:-}" ]; then
            export WINEARCH=win64
        fi
        ;;
esac

# Which build this came from -- to stderr, so a program's own stdout stays
# clean to pipe.
echo "==> Running ${TARGET_NAME} (${BUILD_DIR})${RUN_PREFIX[0]:+ under ${RUN_PREFIX[0]##*/}}" >&2

# Not `exec`, so a failure to start at all can be explained below.
_pmn_status=0
${RUN_PREFIX[@]+"${RUN_PREFIX[@]}"} "$BIN_PATH" "$@" || _pmn_status=$?

# 126 is the shell's "found it, couldn't execute it" -- which is what running
# a binary built for another architecture or OS looks like.
if [ "$_pmn_status" -eq 126 ]; then
    echo "error: '${BIN_PATH}' couldn't be started on this machine. If it is a cross build" >&2
    echo "       (built for another CPU or OS), run it on the target, or install an" >&2
    echo "       emulator -- qemu-user for another CPU, wine for Windows -- and reconfigure" >&2
    echo "       (breeze/scripts/build.sh --preset <name>) so the toolchain picks it up." >&2
fi
exit "$_pmn_status"
