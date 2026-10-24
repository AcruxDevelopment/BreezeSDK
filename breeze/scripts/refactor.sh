#!/usr/bin/env bash
# Applies clang-format and clang-tidy's --fix across this project's own
# C/C++ code. The pre-commit hook only CHECKS; this is the "just fix it"
# counterpart -- review the result with `git diff` afterward, same as any
# auto-formatter.
#
# Defaults to source/ and c-api/ (this template's own-code roots) --
# NEVER walks out/, .cache/, vendor/, or .git/ by default, so it can't
# accidentally spend minutes reformatting/analyzing a fetched dependency's
# entire source tree (e.g. out/build/_deps/*-src/) the way scanning the
# whole repo from "." would. Passing an explicit scope still excludes
# those four directories defensively, in case the scope you give overlaps
# with them.
#
# Usage (from the project root):
#   breeze/scripts/refactor.sh              # every file under source/ and c-api/
#   breeze/scripts/refactor.sh source/Core  # just one file or directory
#   breeze/scripts/refactor.sh --help
set -euo pipefail

case "${1:-}" in
    -h|--help)
        cat <<'EOF'
Usage: breeze/scripts/refactor.sh [scope]

Applies clang-format and clang-tidy's --fix across this project's own
C/C++ code -- review the result with `git diff` afterward. See the
comment at the top of this script for the default scope and why it never
walks out/, .cache/, vendor/, or .git/.

  (no argument)  Every file under source/ and c-api/ (whichever exist).
  scope          Just one file or directory, e.g.:
                   breeze/scripts/refactor.sh source/Core
EOF
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

# _pmn_extend_tool_path: finds Homebrew's keg-only llvm (clang-tidy) on macOS.
source "$SCRIPT_DIR/_common.sh"
_pmn_extend_tool_path

if [ $# -ge 1 ]; then
    scopes=("$1")
else
    scopes=()
    [ -d source ] && scopes+=(source)
    [ -d c-api ] && scopes+=(c-api)
fi

if [ "${#scopes[@]}" -eq 0 ]; then
    echo "No default scope found (expected a source/ and/or c-api/ directory here)." >&2
    exit 1
fi

if ! command -v clang-format >/dev/null 2>&1 && ! command -v clang-tidy >/dev/null 2>&1; then
    echo "error: neither clang-format nor clang-tidy found on PATH. Run breeze/scripts/setup.sh for install guidance." >&2
    exit 1
fi

# A read loop rather than mapfile/readarray: those are bash 4+, and macOS
# ships bash 3.2.
files=()
while IFS= read -r _file; do
    files+=("$_file")
done < <(
    find "${scopes[@]}" \
        \( -path './vendor' -o -path './out' -o -path './.cache' -o -path './.git' \) -prune -o \
        -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.tpp' \) -print \
    | sed 's|^\./||' | sort
)

if [ "${#files[@]}" -eq 0 ]; then
    echo "No C/C++ files found under: ${scopes[*]}"
    exit 0
fi

echo "==> ${#files[@]} file(s) in scope: ${scopes[*]}"

if command -v clang-format >/dev/null 2>&1; then
    echo "==> Running clang-format -i"
    clang-format -i "${files[@]}"
else
    echo "==> Skipping clang-format (not found on PATH -- see breeze/scripts/setup.sh)"
fi

if command -v clang-tidy >/dev/null 2>&1; then
    if [ ! -f compile_commands.json ]; then
        echo "==> Skipping clang-tidy (no compile_commands.json -- run breeze/scripts/build.sh first)"
    else
        echo "==> Running clang-tidy --fix (auto-fixable issues only; build once first if this is stale)"
        for f in "${files[@]}"; do
            clang-tidy --quiet --fix "$f" || true
        done
    fi
else
    echo "==> Skipping clang-tidy (not found on PATH -- see breeze/scripts/setup.sh)"
fi

echo "==> Done. Review the changes: git diff"
