# Shared helpers for breeze/scripts/*.sh. Sourced, never run directly (hence the
# leading underscore and no executable bit); every script sources it after
# it has cd'd to the project root, because both helpers below run
# `cmake -P breeze/cmake/<something>.cmake` relative to that.
#
# There is deliberately no Windows twin of this file: breeze/scripts/*.bat each keep
# their own copy of these two small wrappers as labels (:read_config and
# :resolve_build_dir), because sharing labels between .bat files is more
# fragile than repeating them. What the wrappers *ask* is answered by the
# same cmake scripts either way, so no logic is duplicated -- only the glue.

# Reads one value out of project/Configuration.cmake -- this project's single
# source of truth -- via breeze/cmake/PrintConfig.cmake, instead of hardcoding a
# second copy of a default that can silently drift out of sync. See that
# file for exactly what this strips off of its output.
_pmn_read_config() {
    cmake "-DPRINT_VARS=$1" -P breeze/cmake/PrintConfig.cmake | sed -E 's/^-- [^=]*=//'
}

# _pmn_resolve_build_dir [<name>]
#
# Prints the build directory to use. With a <name> (a preset, or "default")
# that is simply BUILD_OUTPUT_DIR/<name>; without one it is discovered: the
# directory breeze/scripts/build.sh built last, else the only one that exists. If
# neither works, the reason goes to stderr and the return status is 1.
#
# The logic itself is breeze/cmake/BuildDir.cmake's -- see it for the details and
# the one-line answer protocol parsed here.
_pmn_resolve_build_dir() {
    local answer
    # run.sh never needed cmake before it had to ask which build directory to
    # use, so say what's wrong instead of letting the shell's own "command not
    # found" and an empty answer speak for it.
    if ! command -v cmake >/dev/null 2>&1; then
        echo "error: cmake not found on PATH -- it is needed to work out which build directory to use." >&2
        echo "       Put it on PATH, or set BUILD_DIR to the directory explicitly, e.g. BUILD_DIR=out/build/<preset>." >&2
        return 1
    fi
    answer="$(cmake "-DPMN_NAME=${1:-}" -P breeze/cmake/BuildDir.cmake | sed -E 's/^-- //')"
    case "$answer" in
        BUILD_DIR=*)
            printf '%s\n' "${answer#BUILD_DIR=}"
            ;;
        ERROR=*)
            echo "error: ${answer#ERROR=}" >&2
            return 1
            ;;
        *)
            echo "error: breeze/cmake/BuildDir.cmake did not answer as expected: ${answer}" >&2
            return 1
            ;;
    esac
}

# _pmn_record_build_dir <name>
#
# Remembers <name> as the build directory built last, so the next
# `breeze/scripts/run.sh` / `install.sh` / `docs.sh` without a --preset uses it.
_pmn_record_build_dir() {
    cmake "-DPMN_NAME=$1" -DPMN_RECORD=ON -P breeze/cmake/BuildDir.cmake >/dev/null
}

# _pmn_explain_configure_failure <configure-log> [<build-directory>]
#
# Called by breeze/scripts/build.sh after a failed configure. When it was a cross
# build with no target sysroot (the toolchain says so in the first lines of
# its output -- breeze/cmake/toolchains/_common.cmake, pmn_linux_toolchain) AND
# something could not be found, says what that means: the dependency asked
# for a system library (X11, OpenGL, ALSA, ...) that only a target sysroot
# can provide. Silent in every other case -- not every "Could NOT find" is
# this one, and the configure's own error is already on screen.
_pmn_explain_configure_failure() {
    [ -r "$1" ] || return 0
    grep -q 'Cross build without a target sysroot' "$1" || return 0
    grep -qE 'Could NOT find|Could not find|No package .* found' "$1" || return 0
    cat >&2 <<'EOF'

==> Configure failed in a cross build that has no target sysroot, and something
    it needs was not found. That is most likely this: a cross build looks only
    in the target's own root (the cross compiler's /usr/<triplet>), never at the
    host's libraries -- those are for the wrong architecture -- and that root has
    the C/C++ runtime and nothing else. A library such as X11, OpenGL or ALSA is
    there only if you provide it:
      * put a root filesystem for the target, with those libraries installed, in
        .cache/sysroots/linux-<arch>  (arm64, arm32 or x64), or
      * pass -DCMAKE_SYSROOT=<dir> to breeze/scripts/build.sh.
    Then delete the build directory before building again: it keeps what it detected
    about the compiler without the sysroot, and a configure over that stops.
EOF
    if [ -n "${2:-}" ]; then
        echo "      rm -rf $2" >&2
    fi
    echo '    breeze/README.md, "Cross builds and system libraries", has the steps.' >&2
}

# On macOS, Homebrew's llvm formula -- the one that ships clang-tidy -- is
# keg-only: installed, but deliberately not linked into PATH, so a script
# looking for `clang-tidy` can't find it. Add its bin directory to the END of
# PATH (never the front: Apple's clang must stay the one builds use). A
# no-op everywhere else, and when llvm isn't installed.
_pmn_extend_tool_path() {
    [ "$(uname -s)" = Darwin ] || return 0
    local d
    for d in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
        if [ -d "$d" ]; then
            case ":$PATH:" in
                *":$d:"*) ;;
                *) PATH="$PATH:$d" ;;
            esac
            return 0
        fi
    done
    return 0
}
