#!/usr/bin/env bash
# Build Doxygen documentation for every module (see breeze/cmake/Documentation.cmake)
# and print the path to the landing page. A no-op with a clear message if
# Doxygen isn't installed or ENABLE_DOXYGEN=OFF.
#
# Output goes to out/docs/ (DOCS_OUTPUT_DIR in project/Configuration.cmake) --
# note this is a sibling of out/build, not nested inside it, and shared by
# every preset: documentation doesn't depend on which compiler built the
# code. The docs targets just need SOME configured build directory to run
# from, so this uses the one built last unless you pick with --preset. If
# you've overridden DOCS_OUTPUT_DIR at configure time, also set DOCS_DIR here
# to match so the printed path is correct (docs still land in the right
# place either way -- this only affects the message below).
#
# Usage (from the project root):
#   breeze/scripts/docs.sh                              # every module
#   breeze/scripts/docs.sh core_lib                     # just one module's docs (docs_<target>)
#   breeze/scripts/docs.sh --preset linux-x64-gcc       # ... from that preset's build directory
#   breeze/scripts/docs.sh --help
#
# --preset must come first if given at all; --preset=<name> also works. Set
# BUILD_DIR to use an exact build directory instead.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: breeze/scripts/docs.sh [--preset <name>] [module-target-name]

Builds Doxygen documentation for every module (see breeze/cmake/Documentation.cmake)
and prints the path to the landing page. A no-op with a clear message if
Doxygen isn't installed or ENABLE_DOXYGEN=OFF.

  --preset <name>       Run from that preset's build directory
                         (out/build/<name>). Default: the build
                         breeze/scripts/build.sh made last. Must come first if
                         given at all; --preset=<name> also works.
  (no argument)         Build docs for every module.
  module-target-name    Build docs for just that one module (its own
                         docs_<name> target), e.g.:
                           breeze/scripts/docs.sh core_lib

Output goes to out/docs/ (DOCS_OUTPUT_DIR in project/Configuration.cmake), shared
by every preset -- see the comment at the top of this script if you've
overridden that.
HELP
        exit 0
        ;;
esac

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

if [ -z "${BUILD_DIR:-}" ]; then
    # Explains itself and stops if there's nothing to pick.
    BUILD_DIR="$(_pmn_resolve_build_dir "$PRESET")"
fi
DOCS_DIR="${DOCS_DIR:-out/docs}"

if [ ! -d "$BUILD_DIR" ]; then
    echo "error: '${BUILD_DIR}' not found. Run breeze/scripts/build.sh${PRESET:+ --preset $PRESET} first." >&2
    exit 1
fi

echo "==> Using build directory ${BUILD_DIR}"
if [ $# -ge 1 ]; then
    TARGET="docs_$1"
    cmake --build "${BUILD_DIR}" --target "${TARGET}"
    echo "==> Open: ${DOCS_DIR}/$1/html/index.html"
else
    cmake --build "${BUILD_DIR}" --target docs
    if [ -f "${DOCS_DIR}/index.html" ]; then
        echo "==> Open: ${DOCS_DIR}/index.html"
    fi
fi
