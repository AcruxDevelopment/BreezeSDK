#!/usr/bin/env bash
# Configure (if needed) and build the project, preferably with Ninja.
#
# Usage (from the project root):
#   breeze/scripts/build.sh [--preset <name>] [BUILD_TYPE] [CMAKE_ARGS...]
#   breeze/scripts/build.sh --list-presets
#   breeze/scripts/build.sh --help
#
#   --preset <name>  Use a CMakePresets.json preset. A preset selects that
#                    target's toolchain file (breeze/cmake/toolchains/<name>.cmake),
#                    which picks the compiler and declares the DIST_TARGET
#                    together, instead of you having to pass a matching
#                    pair by hand:
#                      breeze/scripts/build.sh --preset windows-x64-mingw64
#                    Each preset builds in its own directory,
#                    out/build/<name>, so switching between presets never
#                    invalidates -- or deletes -- another one's build.
#                    Run --list-presets to see every preset for your OS.
#                    Must come first if given at all; --preset=<name> also
#                    works. Given with no value, or a value that isn't one
#                    of --list-presets' own, this fails fast with that
#                    same preset list shown right there, rather than
#                    letting a typo fall through to a less obvious `cmake`
#                    error further down.
#   BUILD_TYPE       Debug|Release|RelWithDebInfo|MinSizeRel
#                    (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE)
#   CMAKE_ARGS       Anything else is forwarded to `cmake` verbatim, e.g.:
#                      breeze/scripts/build.sh --preset windows-x64-mingw64 Debug -DBUILD_TESTS=ON
#                      breeze/scripts/build.sh -DBUILD_TESTS=ON
#                                (BUILD_TYPE omitted -- recognized by not
#                                starting with "-")
#
# Picking a DIST_TARGET: three ways; the first two set the compiler and the
# label together, and this script rejects mixing --preset with a
# -DDIST_TARGET rather than leaving it ambiguous which one wins.
#   1. --preset <name>       The recommended way; see --list-presets.
#   2. -DCMAKE_TOOLCHAIN_FILE=breeze/cmake/toolchains/<name>.cmake
#      (no --preset)         What a preset does, by hand, as one of
#                             CMAKE_ARGS above.
#   3. -DDIST_TARGET=<value> Sets the label alone, as one of CMAKE_ARGS
#      (no --preset)         above. Without also passing a matching
#                             compiler (or, better, the toolchain file
#                             above), DIST_TARGET is auto-detected from
#                             whatever compiler CMake finds on its own; if
#                             the two disagree, TargetSelection.cmake
#                             FATAL_ERRORs rather than silently building
#                             the wrong toolchain and mislabeling the
#                             result -- see that file and the README.
# Passing --preset together with an explicit -DDIST_TARGET=... in
# CMAKE_ARGS is rejected by this script before cmake even runs: the
# preset's toolchain already declares DIST_TARGET, so a second value
# alongside it is always either redundant (same value) or contradictory
# (different value) -- never useful.
#
# Build directory: out/build/<preset> for --preset <preset>; without a
# preset, out/build/default (the compiler is auto-detected there, so keep
# to one compiler per directory or use presets). Set BUILD_DIR to use an
# exact directory of your own instead. breeze/scripts/run.sh, install.sh and
# docs.sh use the directory built last, or --preset <name> to pick another.
set -euo pipefail
shopt -s nullglob

usage() {
    cat <<'EOF'
Usage: breeze/scripts/build.sh [--preset <name>] [BUILD_TYPE] [CMAKE_ARGS...]
       breeze/scripts/build.sh --list-presets
       breeze/scripts/build.sh --help

  --preset <name>  Use a CMakePresets.json preset: it selects the target's
                    toolchain file (compiler and DIST_TARGET together) and
                    builds in its own directory, out/build/<name>. Must come
                    first if given at all; --preset=<name> also works. Run
                    --list-presets to see every preset for your OS.
  BUILD_TYPE       Debug|Release|RelWithDebInfo|MinSizeRel
                    (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE)
  CMAKE_ARGS       Anything else is forwarded to `cmake` verbatim, e.g.
                   -DDIST_TARGET=<value> or -DBUILD_TESTS=ON.

Don't combine --preset with an explicit -DDIST_TARGET=... in CMAKE_ARGS --
the preset's toolchain already declares one; see the comment at the top of
this script (breeze/scripts/build.sh) and TargetSelection.cmake's "Target selection"
section for why picking a DIST_TARGET is one or the other, not both.

Examples:
  breeze/scripts/build.sh --preset linux-x64-clang
  breeze/scripts/build.sh --preset windows-x64-mingw64 Debug -DBUILD_TESTS=ON
  breeze/scripts/build.sh -DBUILD_TESTS=ON
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

command -v cmake >/dev/null 2>&1 || { echo "error: cmake not found on PATH." >&2; exit 1; }

if [ "${1:-}" = "--list-presets" ]; then
    exec cmake --list-presets
fi

# _pmn_read_config, _pmn_resolve_build_dir, _pmn_record_build_dir.
source "$SCRIPT_DIR/_common.sh"

# Prints CMake's own preset listing (already filtered to this OS by each
# preset's "condition" in CMakePresets.json) to stderr -- used to show the
# actual options right alongside a preset-related error below, instead of
# just telling the user to go run --list-presets separately.
_pmn_show_presets() {
    echo "" >&2
    cmake --list-presets >&2
}

# Membership test against that same listing -- $1 matches a real preset
# name for this OS only if it appears there as a quoted entry (anchored on
# both quote characters so e.g. "windows-x64-mingw32" can't false-match a
# check for "windows-x64-mingw3").
_pmn_known_preset() {
    cmake --list-presets 2>/dev/null | grep -qF "\"$1\""
}

_pmn_has_explicit_dist_target() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -DDIST_TARGET=*) return 0 ;;
        esac
    done
    return 1
}

# --preset must come first if given at all -- see TargetSelection.cmake's
# and CMakePresets.json's own comments for why this is the recommended
# way to pick a non-default DIST_TARGET: its toolchain file sets the
# compiler and the label together, instead of you having to pass both by
# hand.
PRESET=""
case "${1:-}" in
    --preset)
        if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
            echo "error: --preset requires a value, e.g. --preset windows-x64-mingw64" >&2
            _pmn_show_presets
            exit 1
        fi
        PRESET="$2"
        shift 2
        ;;
    --preset=*)
        PRESET="${1#--preset=}"
        shift
        if [ -z "$PRESET" ]; then
            echo "error: --preset= requires a value, e.g. --preset=windows-x64-mingw64" >&2
            _pmn_show_presets
            exit 1
        fi
        ;;
esac

if [ -n "$PRESET" ] && ! _pmn_known_preset "$PRESET"; then
    echo "error: '${PRESET}' is not a preset --list-presets knows about for this OS." >&2
    _pmn_show_presets
    exit 1
fi

# One build directory per preset (out/build/<preset>; "default" when no
# preset was given), so switching presets never has to reuse -- or wipe -- a
# directory configured for another compiler. breeze/cmake/BuildDir.cmake owns the
# layout (project/Configuration.cmake's BUILD_OUTPUT_DIR); an explicit BUILD_DIR
# from the environment beats it, and is then also not recorded as "the one
# built last" (run/install/docs would otherwise be sent to a directory the
# layout doesn't know about).
_pmn_record_build=1
if [ -n "${BUILD_DIR:-}" ]; then
    _pmn_record_build=0
else
    BUILD_DIR="$(_pmn_resolve_build_dir "${PRESET:-default}")"
fi

# If the first remaining argument doesn't start with "-", it's BUILD_TYPE
# and everything after it is CMAKE_ARGS; otherwise there's no BUILD_TYPE
# override and every argument is CMAKE_ARGS. Plain bash "$@"/shift, no
# special-casing needed: unlike Windows cmd.exe (see build.bat), bash
# never splits a "-DFOO=BAR"-style argument on its own "=".
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
    BUILD_TYPE="$1"
    shift
else
    BUILD_TYPE="$(_pmn_read_config DEFAULT_BUILD_TYPE)"
fi
CMAKE_ARGS=("$@")

# ${arr[@]+"${arr[@]}"} rather than a plain "${arr[@]}" wherever an array can be
# empty: under `set -u`, bash before 4.4 -- which includes the 3.2 that macOS
# still ships as /bin/bash -- treats expanding an EMPTY array as an unset
# variable and aborts with "unbound variable".
if [ -n "$PRESET" ] && _pmn_has_explicit_dist_target ${CMAKE_ARGS[@]+"${CMAKE_ARGS[@]}"}; then
    echo "error: both --preset ${PRESET} and an explicit -DDIST_TARGET=... were given." >&2
    echo "       A preset's toolchain already declares DIST_TARGET (and picks the compiler) -- pick one:" >&2
    echo "         breeze/scripts/build.sh --preset ${PRESET}" >&2
    echo "         breeze/scripts/build.sh -DCMAKE_TOOLCHAIN_FILE=breeze/cmake/toolchains/<target>.cmake" >&2
    echo "       See the comment at the top of this script, or TargetSelection.cmake's" >&2
    echo "       \"Target selection\" section, for why these two aren't combined." >&2
    exit 1
fi

# Prefer a pinned ninja (fetched by breeze/scripts/setup.sh -- see
# breeze/cmake/FetchNinja.cmake) over a system one, same "always the pinned copy"
# preference as Doxygen. Needed whether or not --preset is used: every
# preset sets its generator to Ninja but doesn't hardcode which ninja
# binary to use (that would just be TOOLCACHE_DIR's default duplicated a
# third time -- see project/Configuration.cmake) -- CMAKE_MAKE_PROGRAM supplies it
# either way; only -G Ninja itself is skipped below when a preset already
# sets the generator.
TOOLCACHE_DIR="${TOOLCACHE_DIR:-$(_pmn_read_config TOOLCACHE_DIR)}"
NINJA_BIN=""
for _candidate in "${TOOLCACHE_DIR}"/ninja-*/ninja; do
    if [ -x "$_candidate" ]; then
        # Must be absolute: CMake invokes CMAKE_MAKE_PROGRAM from several
        # different working directories during its own internal
        # try-compile steps, where a relative path doesn't resolve.
        NINJA_BIN="$(cd "$(dirname "$_candidate")" && pwd)/$(basename "$_candidate")"
        break
    fi
done

GENERATOR_ARGS=()
if [ -n "$NINJA_BIN" ]; then
    echo "==> Using pinned ninja: ${NINJA_BIN}"
    if [ -z "$PRESET" ]; then
        GENERATOR_ARGS=(-G Ninja "-DCMAKE_MAKE_PROGRAM=${NINJA_BIN}")
    else
        GENERATOR_ARGS=("-DCMAKE_MAKE_PROGRAM=${NINJA_BIN}")
    fi
elif command -v ninja >/dev/null 2>&1; then
    echo "==> Using system ninja: $(command -v ninja)"
    if [ -z "$PRESET" ]; then
        GENERATOR_ARGS=(-G Ninja)
    fi
else
    if [ -n "$PRESET" ]; then
        echo "warning: ninja not found (no pinned copy, none on PATH) -- the '${PRESET}'" >&2
        echo "         preset requires it; configure will likely fail. Run" >&2
        echo "         breeze/scripts/setup.sh to fetch a pinned ninja, or install ninja" >&2
        echo "         yourself." >&2
    else
        echo "warning: ninja not found (no pinned copy, none on PATH) -- falling back to" >&2
        echo "         CMake's default generator for this platform. Run breeze/scripts/setup.sh" >&2
        echo "         to fetch a pinned ninja, or install ninja yourself, for a faster" >&2
        echo "         and more consistent build. Continuing without it." >&2
    fi
fi

CONFIGURE_ARGS=(-S . -B "${BUILD_DIR}")
if [ -n "$PRESET" ]; then
    CONFIGURE_ARGS=(--preset "${PRESET}" "${CONFIGURE_ARGS[@]}")
fi

echo "==> Configuring (${BUILD_TYPE}) into ${BUILD_DIR}/"
if [ -n "$PRESET" ]; then
    echo "    Preset: ${PRESET}"
fi
if [ "${#CMAKE_ARGS[@]}" -gt 0 ]; then
    echo "    Extra CMake arguments: ${CMAKE_ARGS[*]}"
fi
# The configure's output is also kept in a temporary file, only so that a
# failed cross configure can be explained afterwards (_pmn_explain_configure_
# failure, breeze/scripts/_common.sh). Its exit status is still what decides.
# If no temporary file can be made the build goes on without the explanation.
_pmn_cfg_log="$(mktemp "${TMPDIR:-/tmp}/pmn-configure.XXXXXX" 2>/dev/null)" || _pmn_cfg_log=/dev/null
trap 'if [ -f "$_pmn_cfg_log" ]; then rm -f "$_pmn_cfg_log"; fi' EXIT
if ! cmake "${CONFIGURE_ARGS[@]}" ${GENERATOR_ARGS[@]+"${GENERATOR_ARGS[@]}"} -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" ${CMAKE_ARGS[@]+"${CMAKE_ARGS[@]}"} 2>&1 | tee "$_pmn_cfg_log"; then
    _pmn_explain_configure_failure "$_pmn_cfg_log" "${BUILD_DIR:-}"
    exit 1
fi

# Configure succeeded: this is now the build the other scripts default to.
if [ "$_pmn_record_build" = 1 ]; then
    _pmn_record_build_dir "${PRESET:-default}"
fi

echo "==> Building"
cmake --build "${BUILD_DIR}"

echo "==> Done. Run a module with:  breeze/scripts/run.sh <target-name>"
