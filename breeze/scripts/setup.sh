#!/usr/bin/env bash
# One-time (or re-run any time) environment setup for this template. Linux
# and macOS; on Windows it is breeze\scripts\setup.bat.
#
#   1. Checks for the tools this project builds with -- git, CMake 3.25+ and a
#      C++ compiler (both of which are required), and Clang, clang-format,
#      clang-tidy, cross compilers, MinGW and emulators (all optional) -- and
#      offers to install whatever is missing, ONE TOOL AT A TIME, showing
#      the exact command before running it. Nothing is installed without
#      your yes. See breeze/scripts/_tools.sh for what it knows and how.
#   2. Fetches the pinned ninja (breeze/cmake/FetchNinja.cmake) -- used by
#      breeze/scripts/build.sh / build.bat if found (see there); a system ninja
#      still works fine too, this just avoids needing one installed at all.
#      Where upstream ships no ninja binary for your machine, it offers to
#      install one through your package manager instead.
#   3. Fetches the pinned Doxygen (breeze/cmake/FetchDoxygen.cmake) -- NOT
#      required to build the project itself (see breeze/cmake/Documentation.cmake),
#      only to run breeze/scripts/docs.sh / docs.bat afterward.
#   4. Activates the pre-commit hook (breeze/githooks/pre-commit) for this
#      clone, if it's a git repository.
#
# A failure in step 2 or 3 (no pinned binary for this machine, no network)
# is reported and setup carries on -- it used to abort here, before the hook
# was activated.
#
# Usage (from the project root):
#   breeze/scripts/setup.sh [--yes] [--all] [--everything] [--check] [--skip-tools]
#   breeze/scripts/setup.sh --help
set -euo pipefail

_usage() {
    cat <<'EOF'
Usage: breeze/scripts/setup.sh [--yes] [--all] [--everything] [--check] [--skip-tools]

One-time (or re-run any time) environment setup for this template:
  1. Checks the tools the project builds with and offers to install what's
     missing, one tool at a time (git, CMake and a C++ compiler are
     required; Clang, clang-format/clang-tidy, cross compilers, MinGW and
     emulators are optional). Each install shows its exact command and
     waits for your yes.
  2. Fetches the pinned ninja (breeze/cmake/FetchNinja.cmake).
  3. Fetches the pinned Doxygen (breeze/cmake/FetchDoxygen.cmake).
  4. Activates the pre-commit hook (breeze/githooks/pre-commit) for this clone,
     if it's a git repository.

Options:
  -y, --yes       Install the REQUIRED tools without asking. For scripts and
                  CI; without a terminal and without this, nothing is asked
                  and nothing is installed.
      --all       Also install the optional tools without asking (implies
                  --yes). This includes saying yes to the extra-repository
                  questions that come with some of them: enabling pacman's
                  multilib, dnf's COPR for the ARM cross compilers, apt's
                  i386 architecture for wine32.
      --everything  Everything --all does, plus the third-party extras that
                  --all leaves for you to opt into (implies --all). On
                  Arch: the prebuilt 32-bit ARM cross toolchain from the
                  AUR -- four packages built with makepkg (git and
                  base-devel are installed first if missing): a download
                  and a few minutes, no compiling. Run interactively,
                  setup asks about it as its own question instead.
                  Elsewhere there is nothing extra, so it means the same
                  as --all.
      --check     Only report what is and isn't installed; change nothing,
                  fetch nothing. Exits 1 if a required tool is missing.
      --skip-tools  Skip step 1 and go straight to the pinned downloads.

At each question:  y  install it   n  not this one   a  install everything
left   s  skip the rest of the optional tools   q  stop asking.

See the comment at the top of this script for more on each step.
EOF
}

PMN_TOOLS_YES=0
PMN_TOOLS_ALL=0
PMN_TOOLS_HEAVY=0
PMN_TOOLS_CHECK=0
SKIP_TOOLS=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)    _usage; exit 0 ;;
        -y|--yes)     PMN_TOOLS_YES=1 ;;
        --all)        PMN_TOOLS_ALL=1; PMN_TOOLS_YES=1 ;;
        --everything) PMN_TOOLS_HEAVY=1; PMN_TOOLS_ALL=1; PMN_TOOLS_YES=1 ;;
        --check)      PMN_TOOLS_CHECK=1 ;;
        --skip-tools) SKIP_TOOLS=1 ;;
        *)
            echo "error: unknown option '$1'" >&2
            echo "Run breeze/scripts/setup.sh --help for usage." >&2
            exit 1
            ;;
    esac
    shift
done
export PMN_TOOLS_YES PMN_TOOLS_ALL PMN_TOOLS_HEAVY PMN_TOOLS_CHECK

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

# _pmn_tools_run, _pmn_tools_offer and their helpers.
source "$SCRIPT_DIR/_tools.sh"

# ---- 1. tools --------------------------------------------------------------
_tools_rc=0
if [ "$SKIP_TOOLS" = 0 ]; then
    _pmn_tools_run || _tools_rc=$?
    echo
fi

if [ "$PMN_TOOLS_CHECK" = 1 ]; then
    if [ "$_tools_rc" -ne 0 ]; then
        echo "==> Required tools are missing. Run breeze/scripts/setup.sh to install them."
    else
        echo "==> All required tools are present."
    fi
    exit "$_tools_rc"
fi

# Everything below runs CMake scripts.
if ! command -v cmake >/dev/null 2>&1; then
    echo "error: cmake not found on PATH -- nothing below can run without it." >&2
    if [ "$SKIP_TOOLS" = 1 ]; then
        echo "       Re-run without --skip-tools to be offered an install." >&2
    else
        echo "       Install CMake (3.25 or newer), open a new terminal, and re-run this script." >&2
    fi
    exit 1
fi

# ---- 2. pinned ninja -------------------------------------------------------
echo "==> Fetching pinned ninja (breeze/cmake/FetchNinja.cmake)"
if ! cmake -P breeze/cmake/FetchNinja.cmake; then
    echo
    echo "    No pinned ninja here (no upstream binary for this machine, or the"
    echo "    download failed -- see above)."
    if command -v ninja >/dev/null 2>&1; then
        echo "    The ninja on PATH will be used instead: $(command -v ninja)"
    elif [ "$SKIP_TOOLS" = 0 ]; then
        # A build needs SOME ninja; this is the machine-specific moment to say so.
        _pmn_tools_offer ninja || echo "    breeze/scripts/build.sh needs a ninja: install one and put it on PATH."
    else
        echo "    breeze/scripts/build.sh needs a ninja: install one and put it on PATH."
    fi
fi

# ---- 3. pinned Doxygen -----------------------------------------------------
echo
echo "==> Fetching pinned Doxygen (breeze/cmake/FetchDoxygen.cmake)"
if ! cmake -P breeze/cmake/FetchDoxygen.cmake; then
    echo
    echo "    Documentation (breeze/scripts/docs.sh) won't be available: there's no pinned"
    echo "    Doxygen for this machine, or the download failed -- see above."
    echo "    The project itself builds fine without it."
fi

# ---- 4. pre-commit hook ----------------------------------------------------
echo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> Activating pre-commit hook"
    chmod +x breeze/githooks/pre-commit
    git config core.hooksPath breeze/githooks
    echo "    core.hooksPath = breeze/githooks"
else
    echo "==> Skipping pre-commit hook activation (not a git repository yet)"
    echo "    Once you've run 'git init', re-run this script or:"
    echo "      chmod +x breeze/githooks/pre-commit && git config core.hooksPath breeze/githooks"
fi

echo
if [ "$_tools_rc" -ne 0 ]; then
    echo "==> Setup finished, but a required tool is still missing -- see above."
    exit 1
fi
echo "==> Setup complete. breeze/scripts/build.sh and breeze/scripts/docs.sh are ready to use."
