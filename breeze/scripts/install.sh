#!/usr/bin/env bash
# Install this project's own build artifacts to
# out/install/<platform>-<arch>-<compiler>/ (INSTALL_OUTPUT_DIR in
# project/Configuration.cmake; see breeze/cmake/Breeze.cmake's install() DESTINATION paths) --
# the same name as the out/build/<preset> directory they came from, since
# a preset is named after its target.
#
# Always passes --component to `cmake --install`. Without it, any
# vendored/fetched dependency's own install() rules (see
# breeze/cmake/Dependencies.cmake) would also run, typically dumping files under
# CMAKE_INSTALL_PREFIX (e.g. /usr/local) -- COMPONENT is what keeps
# `cmake --install` scoped to just this project's own targets.
#
# Usage (from the project root):
#   breeze/scripts/install.sh [--preset <name>] [BUILD_TYPE]
#   breeze/scripts/install.sh --help
#
#   --preset <name>  Install the build made with that preset
#                    (out/build/<name>). Without it: the build
#                    breeze/scripts/build.sh made last, or the only one that
#                    exists. Must come first if given at all;
#                    --preset=<name> also works.
#   BUILD_TYPE       Debug|Release|RelWithDebInfo|MinSizeRel
#                    (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE) --
#                    only relevant for a Ninja Multi-Config build.
#
# Set BUILD_DIR to install from an exact build directory instead.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Usage: breeze/scripts/install.sh [--preset <name>] [BUILD_TYPE]

Installs this project's own build artifacts to
out/install/<platform>-<arch>-<compiler>/ (INSTALL_OUTPUT_DIR in
project/Configuration.cmake), scoped to just this project via `cmake --install
--component` -- see the comment at the top of this script.

  --preset <name>  Install the build made with that preset (out/build/<name>).
                   Default: the build breeze/scripts/build.sh made last. Must come
                   first if given at all; --preset=<name> also works.
  BUILD_TYPE       Debug|Release|RelWithDebInfo|MinSizeRel
                   (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE) --
                   only relevant for a Ninja Multi-Config build.
HELP
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

command -v cmake >/dev/null 2>&1 || { echo "error: cmake not found on PATH." >&2; exit 1; }

# _pmn_read_config, _pmn_resolve_build_dir, _pmn_record_build_dir. Reading
# values out of project/Configuration.cmake this way -- its single source of truth
# -- is the bug fix that replaced COMPONENT being a literal "demo" here,
# with a comment warning it had to be kept in sync with PROJECT_CODE_NAME by
# hand.
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
BUILD_TYPE="${1:-$(_pmn_read_config DEFAULT_BUILD_TYPE)}"
COMPONENT="$(_pmn_read_config PROJECT_CODE_NAME)"

if [ ! -d "$BUILD_DIR" ]; then
    echo "error: '${BUILD_DIR}' not found. Run breeze/scripts/build.sh${PRESET:+ --preset $PRESET} first." >&2
    exit 1
fi

echo "==> Installing (component: ${COMPONENT}) from ${BUILD_DIR}"
cmake --install "${BUILD_DIR}" --config "${BUILD_TYPE}" --component "${COMPONENT}"
