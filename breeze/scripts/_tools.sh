# Interactive installer for the tools this project builds with. Sourced by
# breeze/scripts/setup.sh (Linux and macOS -- Windows has breeze/scripts/_tools.ps1); never
# run directly, hence the leading underscore and no executable bit.
#
# What it does: works out what OS and package manager it's on, checks each
# tool in a catalog, and for every one that's missing asks -- ONE TOOL AT A
# TIME -- whether to install it, showing the exact command first. Nothing is
# installed without an explicit yes (or --yes / --all, see below).
#
# Written for bash 3.2, which is what macOS ships as /bin/bash: no
# associative arrays, no mapfile, no ${var,,}, and every array that can be
# empty is expanded with the ${arr[@]+"${arr[@]}"} idiom.
#
# Package managers: apt (Debian/Ubuntu), dnf (Fedora/RHEL), pacman (Arch) on
# Linux; Homebrew on macOS. Anything else is told what the tools are and
# left to install them itself. MinGW and the emulators (qemu-user, wine) are
# offered on all three Linux package managers; the Linux-target cross
# compilers (xc-arm64, xc-arm32, xc-x64) are offered wherever a package is
# actually known to produce a working one for THIS project (a real libstdc++
# for the target, laid out under /usr/<triplet> the way breeze/cmake/toolchains/
# expects) -- apt and pacman ship one of their own for some architectures;
# where neither does, dnf's own cross-gcc ships without libstdc++ at all (see
# _pmn_arch_extra_notes), so the working toolchain there comes from a
# community COPR repository instead, offered with its own explicit consent
# separate from the "install this tool?" question (see
# _pmn_dnf_enable_copr), the same way pacman's wine asks separately before
# enabling the multilib repository it needs. Offering a package that would
# then not work is worse than not offering it, so anywhere none of this
# applies, the gap is explained in place (_pmn_arch_extra_notes) rather than
# silently missing.
#
# Entry point: _pmn_tools_run
#   Environment in (set by setup.sh from its flags):
#     PMN_TOOLS_YES=1    install REQUIRED tools without asking
#     PMN_TOOLS_ALL=1    also install OPTIONAL tools without asking
#     PMN_TOOLS_HEAVY=1  on top of ALL: also do the third-party extras that are
#                        otherwise never done without a y typed at their own
#                        question (--all and an earlier "a" don't count) --
#                        today, on Arch, installing the prebuilt 32-bit ARM
#                        cross toolchain from the AUR (see _pmn_offer_aur_arm32).
#                        setup.sh --everything sets this (and ALL, and YES).
#     PMN_TOOLS_CHECK=1  only report; change nothing
#   Returns 0 if every required tool is present at the end, 1 if not.
#
# Without a terminal on stdin and without --yes/--all it does not prompt (a
# CI job must never hang on a question nobody can answer): it reports and
# leaves everything alone.

# Oldest CMake this project supports (cmake_minimum_required in
# CMakeLists.txt, breeze/cmake/Breeze.cmake, and the presets files' cmakeMinimumRequired).
PMN_CMAKE_MIN_MAJOR=3
PMN_CMAKE_MIN_MINOR=25

PMN_TOOLS_YES="${PMN_TOOLS_YES:-0}"
PMN_TOOLS_ALL="${PMN_TOOLS_ALL:-0}"
PMN_TOOLS_HEAVY="${PMN_TOOLS_HEAVY:-0}"
PMN_TOOLS_CHECK="${PMN_TOOLS_CHECK:-0}"

# Answers that carry over from one prompt to the next.
_PMN_ANS_ALL=0        # "a": yes to everything still to come
_PMN_ANS_SKIP_OPT=0   # "s": no to every OPTIONAL tool still to come
_PMN_ANS_QUIT=0       # "q": stop asking altogether
_PMN_APT_UPDATED=0    # apt-get update runs once, before the first apt install

if [ -t 1 ]; then
    _PMN_BOLD=$'\033[1m'; _PMN_DIM=$'\033[2m'; _PMN_GREEN=$'\033[32m'
    _PMN_YELLOW=$'\033[33m'; _PMN_RED=$'\033[31m'; _PMN_RESET=$'\033[0m'
else
    _PMN_BOLD=''; _PMN_DIM=''; _PMN_GREEN=''; _PMN_YELLOW=''; _PMN_RED=''; _PMN_RESET=''
fi

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

_pmn_have() { command -v "$1" >/dev/null 2>&1; }

# The two directories Homebrew's llvm formula is keg-only in (Apple Silicon,
# Intel). Keg-only: installed, but deliberately not linked into PATH, which
# is where clang-tidy comes from.
_pmn_brew_llvm_bin() {
    local d
    for d in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
        if [ -d "$d" ]; then printf '%s\n' "$d"; return 0; fi
    done
    return 1
}

# Sets PMN_OS (linux|macos|other), PMN_ARCH (x64|arm64|arm32|""), PMN_PM
# (apt|dnf|pacman|brew|none) and PMN_SUDO ("" or "sudo").
_pmn_tools_detect() {
    local machine
    case "$(uname -s)" in
        Linux)  PMN_OS=linux ;;
        Darwin) PMN_OS=macos ;;
        *)      PMN_OS=other ;;
    esac

    machine="$(uname -m)"
    # An x86_64 shell under Rosetta 2 on an Apple Silicon Mac still reports
    # x86_64 -- ask about the machine (see breeze/cmake/HostArch.cmake).
    if [ "$PMN_OS" = macos ] && [ "$machine" = x86_64 ] \
        && [ "$(sysctl -in hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
        machine=arm64
    fi
    case "$machine" in
        x86_64|amd64)      PMN_ARCH=x64 ;;
        aarch64|arm64)     PMN_ARCH=arm64 ;;
        arm*)              PMN_ARCH=arm32 ;;
        *)                 PMN_ARCH="" ;;
    esac

    PMN_PM=none
    if [ "$PMN_OS" = macos ]; then
        # Homebrew is often installed but not on PATH in a fresh shell.
        if ! _pmn_have brew; then
            local b
            for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
                if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
            done
        fi
        if _pmn_have brew; then PMN_PM=brew; fi
    elif [ "$PMN_OS" = linux ]; then
        if   _pmn_have apt-get; then PMN_PM=apt
        elif _pmn_have dnf;     then PMN_PM=dnf
        elif _pmn_have pacman;  then PMN_PM=pacman
        fi
    fi

    # Root is only a question for Linux's system package managers. Homebrew
    # refuses to run as root and never needs it -- and decided HERE, before
    # a fresh Homebrew exists, this would otherwise be computed against
    # PMN_PM=none.
    PMN_SUDO=""
    if [ "$PMN_OS" = linux ] && [ "$(id -u)" != 0 ]; then
        if _pmn_have sudo; then PMN_SUDO=sudo; else PMN_SUDO="?"; fi
    fi
}

# "3.28.3" for the installed cmake, or "" if there isn't one.
_pmn_cmake_version() {
    _pmn_have cmake || return 0
    cmake --version 2>/dev/null | sed -n '1s/^[^0-9]*\([0-9][0-9.]*\).*/\1/p'
}

# 0 if the installed cmake is at least the minimum.
_pmn_cmake_new_enough() {
    local v major minor
    v="$(_pmn_cmake_version)"
    [ -n "$v" ] || return 1
    major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
    if [ "$major" -gt "$PMN_CMAKE_MIN_MAJOR" ]; then return 0; fi
    [ "$major" -eq "$PMN_CMAKE_MIN_MAJOR" ] && [ "$minor" -ge "$PMN_CMAKE_MIN_MINOR" ]
}

# macOS: /usr/bin/git, /usr/bin/clang and friends exist on every Mac as
# stubs that pop up an installer dialog when run without the Command Line
# Tools -- `command -v` finds them regardless. The developer directory is
# what says whether real tools sit behind them.
_pmn_clt_installed() {
    local dir
    dir="$(xcode-select -p 2>/dev/null)" || return 1
    [ -x "$dir/usr/bin/clang" ]
}

# _pmn_tool_status <id>: prints "ok <detail>", "old <detail>" or "missing".
_pmn_tool_status() {
    local v p
    case "$1" in
        clt)
            if _pmn_clt_installed; then echo "ok $(xcode-select -p)"; else echo missing; fi ;;
        brew)
            if _pmn_have brew; then echo "ok $(command -v brew)"; else echo missing; fi ;;
        git)
            if _pmn_have git; then echo "ok $(git --version | sed 's/^git version //')"; else echo missing; fi ;;
        cmake)
            v="$(_pmn_cmake_version)"
            if [ -z "$v" ]; then echo missing
            elif _pmn_cmake_new_enough; then echo "ok $v"
            else echo "old $v"; fi ;;
        cxx)
            if   _pmn_have g++;     then echo "ok g++ $(g++ -dumpversion 2>/dev/null)"
            elif _pmn_have clang++; then echo "ok clang++"
            elif _pmn_have c++;     then echo "ok c++"
            else echo missing; fi ;;
        clang)
            if _pmn_have clang++; then echo "ok $(clang++ --version 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"; else echo missing; fi ;;
        clang-format|clang-tidy)
            if _pmn_have "$1"; then echo "ok $(command -v "$1")"
            elif p="$(_pmn_brew_llvm_bin)" && [ -x "$p/$1" ]; then echo "ok $p/$1"
            else echo missing; fi ;;
        # Compiled and linked for real, not just found on PATH -- see
        # _pmn_cross_probe for why a mere `command -v` isn't enough.
        xc-arm64)  _pmn_cross_status aarch64-linux-gnu ;;
        xc-arm32)  _pmn_cross_status arm-linux-gnueabihf ;;
        xc-x64)    _pmn_cross_status x86_64-linux-gnu ;;
        mingw64)   if _pmn_have x86_64-w64-mingw32-g++;    then echo "ok"; else echo missing; fi ;;
        mingw32)   if _pmn_have i686-w64-mingw32-g++;      then echo "ok"; else echo missing; fi ;;
        qemu)      if _pmn_have qemu-aarch64 || _pmn_have qemu-arm || _pmn_have qemu-x86_64; then echo "ok"; else echo missing; fi ;;
        wine)
            if _pmn_have wine || _pmn_have wine64; then
                if [ "$PMN_PM" = apt ] && [ "$PMN_ARCH" = x64 ] && ! _pmn_apt_wine64_installed; then
                    echo "partial wine64 is missing (64-bit Windows programs need it)"
                elif [ "$PMN_PM" = apt ] && [ "$PMN_ARCH" = x64 ] && ! _pmn_apt_wine32_installed; then
                    echo "partial wine32:i386 is missing (32-bit Windows programs need it)"
                else
                    echo "ok"
                fi
            else
                echo missing
            fi ;;
        ninja)     if _pmn_have ninja; then echo "ok $(ninja --version 2>/dev/null)"; else echo missing; fi ;;
        *)         echo missing ;;
    esac
}

# ---------------------------------------------------------------------------
# The catalog
#
#   id | kind | label | why | apt | dnf | pacman | brew
#
# "-" means "not offered through that package manager". Rows are filtered per
# platform by _pmn_tools_rows below, and listed in the order they're asked.
# ---------------------------------------------------------------------------

_pmn_row_cat() {
    case "$1" in
        git)          echo "git|required|Git|FetchContent clones dependencies (fmt) with it|git|git|git|git" ;;
        cmake)        echo "cmake|required|CMake $PMN_CMAKE_MIN_MAJOR.$PMN_CMAKE_MIN_MINOR or newer|configures and drives every build|cmake|cmake|cmake|cmake" ;;
        cxx)          echo "cxx|required|C++ compiler (GCC)|compiles the project|g++|gcc-c++|gcc|-" ;;
        clang)        echo "clang|optional|Clang|the linux-*-clang presets (GCC alone is enough otherwise)|clang|clang|clang|-" ;;
        clang-format) echo "clang-format|optional|clang-format|breeze/scripts/refactor.sh and the pre-commit hook|clang-format|clang-tools-extra|clang|clang-format" ;;
        clang-tidy)   echo "clang-tidy|optional|clang-tidy|breeze/scripts/refactor.sh and the pre-commit hook|clang-tidy|clang-tools-extra|clang|llvm" ;;
        xc-arm64)     echo "xc-arm64|optional|AArch64 cross compiler|the linux-arm64-* presets, built from this machine|g++-aarch64-linux-gnu|aarch64-linux-gnu-binutils aarch64-linux-gnu-gcc aarch64-linux-gnu-glibc|aarch64-linux-gnu-gcc|-" ;;
        xc-arm32)     echo "xc-arm32|optional|32-bit ARM cross compiler|the linux-arm32-* presets, built from this machine|g++-arm-linux-gnueabihf|arm-linux-gnueabihf-binutils arm-linux-gnueabihf-gcc arm-linux-gnueabihf-glibc|-|-" ;;
        xc-x64)       echo "xc-x64|optional|x86-64 cross compiler|the linux-x64-* presets, built from this machine|g++-x86-64-linux-gnu|-|-|-" ;;
        mingw64)      echo "mingw64|optional|MinGW-w64 (64-bit Windows)|the windows-x64-mingw64 preset, cross-built from Linux|g++-mingw-w64-x86-64|mingw64-gcc-c++|mingw-w64-gcc|-" ;;
        mingw32)      echo "mingw32|optional|MinGW-w64 (32-bit Windows)|the windows-x86-mingw32 preset, cross-built from Linux|g++-mingw-w64-i686|mingw32-gcc-c++|mingw-w64-gcc|-" ;;
        qemu)         echo "qemu|optional|qemu-user|runs ARM cross builds (breeze/scripts/run.sh, ctest)|qemu-user|qemu-user|qemu-user|-" ;;
        # apt names wine64 outright: `wine` only depends on "wine64 | wine32",
        # an either/or, so `apt-get install wine wine32:i386` lets apt satisfy
        # it with wine32 alone and leave wine64 out (it installs wine,
        # wine32:i386 and libwine:i386 and nothing else). Without wine64 no
        # 64-bit Windows program -- windows-x64-mingw64 -- can run at all.
        wine)         echo "wine|optional|wine|runs MinGW cross builds (breeze/scripts/run.sh, ctest)|wine wine64 wine32:i386|wine|wine|-" ;;
        ninja)        echo "ninja|required|Ninja|the build generator (no pinned download exists for this machine)|ninja-build|ninja-build|ninja|ninja" ;;
        clt)          echo "clt|required|Xcode Command Line Tools|Apple Clang, git and make: the compiler for the macos-* presets|-|-|-|-" ;;
        brew)         echo "brew|required|Homebrew|installs CMake and the other tools below|-|-|-|-" ;;
    esac
}

# The ids to consider on this platform, in the order they are asked.
_pmn_tools_ids() {
    if [ "$PMN_OS" = macos ]; then
        echo "clt brew cmake clang-format clang-tidy"
        return
    fi
    local ids="git cmake cxx clang clang-format clang-tidy"
    # Cross toolchains: only for architectures this machine can build FOR
    # without being them, and only where a package (or, for dnf, a COPR --
    # see _pmn_dnf_copr_for) is verified to actually provide a working one --
    # confirmed against each distro's own package pages (and, for apt and
    # the pacman rows below, this project's own users), not assumed from one
    # distro's naming carrying over to another's. See _pmn_arch_extra_notes
    # for what's deliberately still left out here and why: Fedora's own
    # repos have no C++-capable Linux-target cross compiler at all (its
    # cross-gcc packages ship no libstdc++, which is why dnf's rows below
    # point at a COPR instead), no package manager here has one for
    # x86-64-from-arm64, and pacman has no OFFICIAL package for 32-bit ARM
    # either (AUR-only -- see _pmn_offer_aur_arm32).
    case "$PMN_PM" in
        apt)
            case "$PMN_ARCH" in
                x64)   ids="$ids xc-arm64 xc-arm32 mingw64 mingw32 qemu wine" ;;
                arm64) ids="$ids xc-x64 xc-arm32 mingw64 mingw32 qemu" ;;
            esac
            ;;
        pacman)
            case "$PMN_ARCH" in
                # xc-arm32 has no pacman package (its row says "-"): it is
                # listed so the report shows whether it works, and
                # _pmn_offer_aur_arm32 does the installing.
                x64)   ids="$ids xc-arm64 xc-arm32 mingw64 mingw32 qemu wine" ;;
                arm64) ids="$ids mingw64 mingw32 qemu" ;;
            esac
            ;;
        dnf)
            case "$PMN_ARCH" in
                x64)   ids="$ids xc-arm64 xc-arm32 mingw64 mingw32 qemu wine" ;;
                arm64) ids="$ids xc-arm32 mingw64 mingw32 qemu wine" ;;
                *)     ids="$ids mingw64 mingw32 qemu wine" ;;
            esac
            ;;
    esac
    echo "$ids"
}

# -----------------------------------------------------------------------
# Distro situations the catalog's plain "-" (not offered through this
# package manager) doesn't explain on its own. Printed once, right after
# the report, so "why isn't X in this list" has an answer instead of
# looking like an oversight.
# -----------------------------------------------------------------------
_pmn_arch_extra_notes() {
    case "$PMN_PM" in
        apt)
            if [ "$PMN_ARCH" = arm64 ] && ! _pmn_have wine && ! _pmn_have wine64; then
                _pmn_note "    wine isn't offered here: Debian/Ubuntu do package it for arm64, but it's"
                _pmn_note "    had long-standing arm64-host reliability problems there (hangs on"
                _pmn_note "    startup on recent releases -- e.g. Ubuntu bug 2102681) serious enough"
                _pmn_note "    that offering it would likely just fail. Install wine by hand if you"
                _pmn_note "    want to try it anyway; the windows-*-mingw* presets don't need it --"
                _pmn_note "    it's ctest and breeze/scripts/run.sh that use it to run what they build."
            fi
            ;;
        dnf)
            _pmn_note "    Fedora's own gcc-aarch64-linux-gnu / gcc-arm-linux-gnu / gcc-x86-64-linux-gnu"
            _pmn_note "    packages ship no libstdc++ -- their own package description says"
            _pmn_note "    cross-building userspace (i.e. non-kernel) programs isn't supported, and a"
            _pmn_note "    C++ project like this one needs it. Where the list above offers an AArch64"
            _pmn_note "    or 32-bit ARM cross compiler on dnf, it's from lantw44's COPR instead (a"
            _pmn_note "    full GCC+glibc build, not Fedora's own package) -- accepting it enables"
            _pmn_note "    that community repository, with its own separate confirmation. It can lag"
            _pmn_note "    a new Fedora release by a while, so a just-released Fedora may not have a"
            _pmn_note "    build there yet. MinGW (Windows) cross-compilation is a separate, complete"
            _pmn_note "    Fedora project and works fine through Fedora's own mingw64-gcc-c++ /"
            _pmn_note "    mingw32-gcc-c++ -- no COPR needed."
            ;;
        pacman)
            if [ "$PMN_ARCH" = x64 ] && [ "$(_pmn_tool_status xc-arm32 | cut -d' ' -f1)" != ok ]; then
                _pmn_note "    32-bit ARM cross compiler (linux-arm32-*): no official Arch package. The AUR"
                _pmn_note "    has ARM's own prebuilt GNU toolchain split into four packages"
                _pmn_note "    (arm-linux-gnueabihf-{binutils,glibc-headers,glibc,gcc}-bin): a download of a"
                _pmn_note "    couple of hundred MB, not a compile. It is offered as its own question when"
                _pmn_note "    you run this interactively; breeze/scripts/setup.sh --everything does it without"
                _pmn_note "    asking. (Installing just arm-linux-gnueabihf-gcc-bin through an AUR helper"
                _pmn_note "    builds the source-built binutils and glibc instead -- hours, and a toolchain"
                _pmn_note "    whose parts don't fit together.)"
            elif [ "$PMN_ARCH" = arm64 ]; then
                _pmn_note "    32-bit ARM cross compiler (linux-arm32-*): not offered here -- the prebuilt"
                _pmn_note "    AUR toolchain (arm-linux-gnueabihf-*-bin) is ARM's x86-64-hosted build, which"
                _pmn_note "    can't run on an arm64 machine. ARM publishes an AArch64-hosted build of the"
                _pmn_note "    same toolchain (developer.arm.com, GNU toolchain downloads) to unpack by hand."
            fi
            ;;
    esac
    case "$PMN_PM" in
        dnf|pacman)
            if [ "$PMN_ARCH" = arm64 ]; then
                _pmn_note "    x86-64 cross compiler (linux-x64-* built from arm64): apt ships one"
                _pmn_note "    (g++-x86-64-linux-gnu); no dnf or pacman equivalent is known to exist yet."
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------
# Does a cross compiler WORK, or does it merely exist?
#
# `command -v arm-linux-gnueabihf-g++` can't tell, and a half-installed
# toolchain passes it: setup.sh used to report the 32-bit ARM compiler as
# installed while its g++ couldn't assemble a single file -- the assembler
# and C library on the machine came from a different package set than the
# compiler (see _pmn_aur_arm32_build). So the cross-compiler rows compile
# and LINK a small C++ program, which needs every piece a real build needs
# (the target's assembler, headers, libstdc++, crt1.o and libc), and
# anything that fails reads "partial" instead of "ok". What comes out is a
# foreign-architecture executable, so nothing is run.
# -----------------------------------------------------------------------

# _pmn_cross_probe <compiler>: 0 if <compiler> builds and links a C++
# program for its target. Otherwise 1, with the compiler's first error line
# on stdout.
_pmn_cross_probe() {
    local cxx="$1" dir out="" rc=0 line
    dir="$(mktemp -d 2>/dev/null)" || return 0    # can't probe: don't cry wolf
    printf '#include <iostream>\nint main() { std::cout << 1; }\n' > "$dir/probe.cpp"
    if _pmn_have timeout; then
        out="$(timeout 120 "$cxx" "$dir/probe.cpp" -o "$dir/probe" 2>&1 </dev/null)" || rc=$?
    else
        out="$("$cxx" "$dir/probe.cpp" -o "$dir/probe" 2>&1 </dev/null)" || rc=$?
    fi
    rm -rf "$dir"
    [ "$rc" = 0 ] && return 0
    line="$(printf '%s\n' "$out" | grep -i -m1 'error')" || line=""
    [ -n "$line" ] || line="$(printf '%s\n' "$out" | sed -n '1p')"
    [ -n "$line" ] || line="exit status $rc"
    printf '%s\n' "$line" | sed 's/^[[:space:]]*//' | cut -c1-160
    return 1
}

# _pmn_cross_status <triplet>: the catalog status ("ok", "missing" or
# "partial <detail>") of <triplet>-g++.
_pmn_cross_status() {
    local cxx="$1-g++" why
    if ! _pmn_have "$cxx"; then echo missing; return 0; fi
    if why="$(_pmn_cross_probe "$cxx")"; then
        echo ok
    else
        echo "partial can't build a test program: $why"
    fi
}

# _pmn_cross_diagnose <compiler>: the facts that explain a cross compiler
# that doesn't work -- which target it was built for, which sysroot and
# assembler it looks for, and which of its packages are installed. Readable
# as it is, and complete enough to paste into a bug report.
_pmn_cross_diagnose() {
    local cxx="$1" opt triplet
    triplet="${cxx%-g++}"
    for opt in -dumpmachine -print-sysroot -print-prog-name=as; do
        _pmn_note "      $cxx $opt  ->  $("$cxx" "$opt" 2>&1 </dev/null | sed -n '1p')"
    done
    if _pmn_have pacman; then
        _pmn_note "      installed ${triplet}-* packages: $(pacman -Qq 2>/dev/null | grep "^${triplet}-" | tr '\n' ' ')"
    fi
}

# -----------------------------------------------------------------------
# Never answered for you: the slow or third-party extras (today, the AUR
# toolchain below). _pmn_confirm takes `--all`, and an earlier "a", as a
# yes; these don't count here -- only --everything (which never reaches
# this) or a y typed at this very question. 0 for yes.
# -----------------------------------------------------------------------
_pmn_confirm_heavy() {
    local ans
    [ "$_PMN_ANS_QUIT" = 1 ] && return 1
    [ "$_PMN_ANS_SKIP_OPT" = 1 ] && return 1
    [ -t 0 ] || return 1
    if ! IFS= read -r -p "  $1 [y/N] " ans; then
        echo
        _PMN_ANS_QUIT=1
        return 1
    fi
    case "$ans" in y|Y|yes|YES|Yes) return 0 ;; esac
    return 1
}

# After a failed AUR build or install: what the usual causes look like, and
# what to do about each. This script can't tell them apart from an exit
# status alone.
_pmn_note_aur_hint() {
    _pmn_note "    If the output above ends in a key error ('PGP keys need importing', 'problem"
    _pmn_note "    importing keys', 'unknown public key'): import the key it names (gpg --recv-keys"
    _pmn_note "    <ID>; for a kernel.org address, gpg --auto-key-locate nodefault,wkd --locate-keys"
    _pmn_note "    <address>) and run this again. If it ends in a conflict ('are in conflict',"
    _pmn_note "    'conflicting files', 'exists in filesystem'): remove the package that owns the"
    _pmn_note "    file or that is named, and run this again. Either way the packages' pages say"
    _pmn_note "    more: https://aur.archlinux.org/packages/arm-linux-gnueabihf-gcc-bin"
}

# -----------------------------------------------------------------------
# The 32-bit ARM cross compiler on Arch (x64 hosts).
#
# Arch has no official package for it. The AUR has two families:
#
#   * arm-linux-gnueabihf-{binutils,linux-api-headers,gcc-stage1,
#     glibc-headers,gcc-stage2,glibc,gcc}: GCC bootstrapped from source,
#     stage by stage. Hours of compiling, and each stage conflicts with the
#     one before it.
#   * arm-linux-gnueabihf-{binutils,glibc-headers,glibc,gcc}-bin: ARM's own
#     x86-64-hosted GNU toolchain (arm-none-linux-gnueabihf, 15.2.rel1),
#     prebuilt and split into four packages that each `provide` the name of
#     their source-built twin. A download, not a compile -- and x86-64 only,
#     which is why arm64 hosts aren't offered it.
#
# `yay -S arm-linux-gnueabihf-gcc-bin` -- what this script used to run, in
# three steps -- looks like the second family and builds the first. The
# package's dependencies are written as the generic names (binutils, glibc,
# glibc-headers); a helper looks for a package of exactly that name first,
# finds the source-built one, and only then at what merely provides it. The
# result was hours of compiling and a MIXED toolchain: ARM's prebuilt
# compiler (which looks for its assembler and C library where ARM's layout
# puts them) next to a source-built binutils and glibc (which put them
# somewhere else). It "compiled okay" and then failed every use:
#
#   linux-arm32-gcc    "Fatal error: invalid -march= option: `armv7-a+simd'"
#                      -- that is the host's x86 assembler: the compiler
#                      couldn't find its own, so it fell back to PATH.
#   linux-arm32-clang  "Scrt1.o: file not recognized" -- the sysroot the
#                      compiler reports (/arm-none-linux-gnueabihf/libc)
#                      isn't there, so the linker found the host's.
#
# So the four -bin packages are installed by name, as ONE pacman
# transaction: build each from its AUR repository with makepkg (no
# dependency resolution by an AUR helper to get wrong -- and none needed,
# which is also why no helper has to be installed), then `pacman -U` them
# together, so every dependency among them is satisfied by another of the
# four and nothing is built from source. --ask 4 is pacman's pre-answer-yes
# for "X and Y are in conflict. Remove Y?" (its default, which --noconfirm
# takes, is No): the -bin packages conflict with their source-built twins,
# and an earlier source build is exactly the state a repair starts from. It
# answers yes for any conflicting package in that transaction, not only
# those, and the prompt says so.
# -----------------------------------------------------------------------
_PMN_ARM32_AUR_PACKAGES="arm-linux-gnueabihf-binutils-bin arm-linux-gnueabihf-glibc-headers-bin arm-linux-gnueabihf-glibc-bin arm-linux-gnueabihf-gcc-bin"

# _pmn_aur_arm32_build: clones the four AUR repositories, builds them with
# makepkg, and installs them together. The work directory is removed on
# success; after a failure it stays, with the (shared) source download in it,
# so running this again doesn't fetch ARM's toolchain a second time.
_pmn_aur_arm32_build() {
    local work pkg dir stage staged=() files=() f
    if [ "$(id -u)" = 0 ]; then
        _pmn_say "    ${_PMN_RED}can't build an AUR package as root${_PMN_RESET} -- makepkg refuses to."
        _pmn_say "    Re-run as a normal user with sudo."
        return 1
    fi
    if [ "$PMN_SUDO" = "?" ]; then
        _pmn_say "    ${_PMN_RED}cannot install the packages:${_PMN_RESET} installing needs root, and sudo isn't available."
        return 1
    fi
    if ! { _pmn_have git && _pmn_have makepkg && _pmn_have fakeroot; }; then
        _pmn_pkg_install "git base-devel" || return 1
    fi

    # Under the cache directory, not /tmp: /tmp is RAM-backed on Arch, and
    # ARM's toolchain unpacks to well over a gigabyte.
    work="${XDG_CACHE_HOME:-$HOME/.cache}/pmn-aur-arm32"
    mkdir -p "$work/src" "$work/git" "$work/pkgs" || return 1
    rm -f "$work"/pkgs/*

    # All four PKGBUILDs download the same ARM tarball: SRCDEST makes makepkg
    # fetch it once and reuse it (it reads SRCDEST/PKGDEST from the
    # environment, ahead of makepkg.conf). --clean drops each build's
    # unpacked copy as soon as its package exists, so only one is on disk at a
    # time; --nodeps because these only repackage a binary release -- the
    # dependency check that matters happens at install, below.
    for pkg in $_PMN_ARM32_AUR_PACKAGES; do
        dir="$work/git/$pkg"
        rm -rf "$dir"
        _pmn_run_shown git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$dir" || return 1
        # The AUR answers a clone of a name it doesn't have with an empty
        # repository and a warning, not an error -- which is what a package
        # that was renamed, merged into another or removed looks like.
        if [ ! -f "$dir/PKGBUILD" ]; then
            _pmn_say "    ${_PMN_RED}the AUR repository ${pkg} has no PKGBUILD${_PMN_RESET} -- the package may have been renamed, merged into another or removed."
            _pmn_say "    Look for what replaced it: https://aur.archlinux.org/packages?K=arm-linux-gnueabihf"
            return 1
        fi
        (cd "$dir" && _pmn_run_shown env SRCDEST="$work/src" PKGDEST="$work/pkgs" \
            makepkg --force --clean --nodeps --noconfirm) || return 1
    done

    for f in "$work"/pkgs/*.pkg.tar.*; do
        [ -e "$f" ] || continue
        case "$f" in *.sig|*-debug-*) continue ;; esac
        files+=("$f")
    done
    if [ "${#files[@]}" -eq 0 ]; then
        _pmn_say "    ${_PMN_RED}makepkg finished, but left no package in${_PMN_RESET} $work/pkgs"
        return 1
    fi

    # The bootstrap compilers of an earlier source build install the same
    # /usr/bin/arm-linux-gnueabihf-* names as gcc-bin, with no conflict
    # declared between them, so they have to go first (plain -R, not -s,
    # which would also take what was installed for later).
    for stage in arm-linux-gnueabihf-gcc-stage2 arm-linux-gnueabihf-gcc-stage1; do
        if pacman -Qq "$stage" >/dev/null 2>&1; then staged+=("$stage"); fi
    done
    if [ "${#staged[@]}" -gt 0 ]; then
        _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} pacman -R --noconfirm "${staged[@]}" || return 1
    fi

    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} pacman -U --noconfirm --needed --ask 4 "${files[@]}" || return 1
    rm -rf "$work"
}

# _pmn_report_arm32_install: after the install itself reported success --
# which says nothing about whether the compiler works. Says what it found.
_pmn_report_arm32_install() {
    local why
    if ! _pmn_have arm-linux-gnueabihf-g++; then
        _pmn_say "    ${_PMN_YELLOW}the packages installed, but arm-linux-gnueabihf-g++ still isn't on PATH${_PMN_RESET} -- check the output above."
        return 1
    fi
    if why="$(_pmn_cross_probe arm-linux-gnueabihf-g++)"; then
        _pmn_say "    ${_PMN_GREEN}installed${_PMN_RESET} -- and it compiles and links a test program"
        return 0
    fi
    _pmn_say "    ${_PMN_YELLOW}installed, but arm-linux-gnueabihf-g++ can't build a test program:${_PMN_RESET} $why"
    _pmn_cross_diagnose arm-linux-gnueabihf-g++
    _pmn_note "    That is what breeze/cmake/toolchains/ would hit too. Paste the lines above into an"
    _pmn_note "    issue: they say which assembler and sysroot the compiler looks for."
    return 1
}

# -----------------------------------------------------------------------
# _pmn_offer_aur_arm32: the pacman/x64 half of the situation
# _pmn_arch_extra_notes describes. Offered when the 32-bit ARM compiler is
# missing -- or present but unable to build anything, the state the old
# three-step source build left behind; the same install repairs it.
#
# Never done without an answer from you: --all and an earlier "a" don't
# count (see _pmn_confirm_heavy), only --everything or a y at this question.
# It runs community PKGBUILDs as you and downloads ARM's toolchain, so it
# is a separate decision from "install the usual tools".
#
# Uses bash's dynamic scoping deliberately: `offered` and `skipped_optional`
# are the CALLER's (_pmn_tools_run's) `local` variables, still in scope
# here since this is called from within that function, so accepting or
# declining this folds into the SAME summary the catalog rows use instead
# of printing a separate one.
# -----------------------------------------------------------------------
_pmn_offer_aur_arm32() {
    [ "$PMN_PM" = pacman ] && [ "$PMN_ARCH" = x64 ] || return 0
    [ "$_PMN_ANS_QUIT" = 1 ] && return 0

    local state detail label="32-bit ARM cross compiler (AUR, prebuilt)"
    state="$(_pmn_tool_status xc-arm32)"
    [ "${state%% *}" = ok ] && return 0
    detail="${state#* }"; [ "$detail" = "$state" ] && detail=""

    if ! _pmn_heavy_wanted; then
        if [ "$PMN_TOOLS_ALL" = 1 ] || [ "$_PMN_ANS_SKIP_OPT" = 1 ] || [ ! -t 0 ]; then
            skipped_optional="${skipped_optional:+$skipped_optional, }$label"
            return 0
        fi
    fi

    offered=$((offered + 1))
    _pmn_say
    _pmn_say "  ${_PMN_BOLD}${label}${_PMN_RESET} -- the linux-arm32-* presets, built from this machine"
    if [ -n "$detail" ]; then
        _pmn_note "    arm-linux-gnueabihf-g++ is already installed, but it $detail"
        _pmn_note "    This install repairs that: it replaces the pieces that don't belong together."
    fi
    _pmn_note "    No official Arch package exists for this (see the note above). The AUR has"
    _pmn_note "    ARM's own GNU toolchain (15.2.rel1, x86-64 hosts) repackaged as four prebuilt"
    _pmn_note "    packages -- arm-linux-gnueabihf-{binutils,glibc-headers,glibc,gcc}-bin: a"
    _pmn_note "    download of a couple of hundred MB and a few minutes, no compiling. They are"
    _pmn_note "    community-maintained, not reviewed by Arch, and their PKGBUILDs run as you."
    _pmn_note "    Each is built from its AUR repository with makepkg (git and base-devel are"
    _pmn_note "    installed first if missing), then all four are installed in ONE pacman"
    _pmn_note "    transaction, with --ask 4: pacman's pre-answer-yes for \"X and Y are in"
    _pmn_note "    conflict. Remove Y?\", whose default (and --noconfirm's) is No. That is how a"
    _pmn_note "    source-built arm-linux-gnueabihf-binutils or -glibc from an earlier attempt"
    _pmn_note "    gets replaced; it answers yes for any conflicting package in that transaction,"
    _pmn_note "    not only those. Leftover gcc-stage1/stage2 compilers are removed first."
    if _pmn_heavy_wanted || _pmn_confirm_heavy "Build and install these four packages now?"; then
        if _pmn_aur_arm32_build; then
            _pmn_report_arm32_install || true
        else
            _pmn_say "    ${_PMN_RED}the install failed${_PMN_RESET} -- see the output above."
            _pmn_note_aur_hint
        fi
    else
        skipped_optional="${skipped_optional:+$skipped_optional, }$label"
    fi
}

# Field <n> (1-based) of a catalog row. A `read` into named variables rather
# than word-splitting the row: the rows contain "*" (linux-*-clang), and an
# unquoted expansion would be subject to pathname globbing.
_pmn_field() {
    local f1 f2 f3 f4 f5 f6 f7 f8
    IFS='|' read -r f1 f2 f3 f4 f5 f6 f7 f8 <<< "$1"
    case "$2" in
        1) printf '%s\n' "$f1" ;; 2) printf '%s\n' "$f2" ;; 3) printf '%s\n' "$f3" ;;
        4) printf '%s\n' "$f4" ;; 5) printf '%s\n' "$f5" ;; 6) printf '%s\n' "$f6" ;;
        7) printf '%s\n' "$f7" ;; 8) printf '%s\n' "$f8" ;;
    esac
}

# The package(s) that provide a row's tool through the current package
# manager, or "" if it isn't offered there.
_pmn_row_packages() {
    local row="$1" col
    case "$PMN_PM" in
        apt) col=5 ;; dnf) col=6 ;; pacman) col=7 ;; brew) col=8 ;; *) return 0 ;;
    esac
    local p
    p="$(_pmn_field "$row" "$col")"
    [ "$p" = "-" ] && p=""
    printf '%s\n' "$p"
}

# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

_pmn_say()  { printf '%s\n' "$*"; }
_pmn_note() { printf '%s\n' "${_PMN_DIM}$*${_PMN_RESET}"; }

# Would an OPTIONAL tool be offered (asked about, or installed by --all) at
# this point? If not, the caller skips it silently and mentions it once at
# the end, instead of printing a "left alone" block for each.
_pmn_optional_wanted() {
    if [ "$_PMN_ANS_QUIT" = 1 ] || [ "$_PMN_ANS_SKIP_OPT" = 1 ]; then return 1; fi
    if [ "$PMN_TOOLS_ALL" = 1 ] || [ "$_PMN_ANS_ALL" = 1 ]; then return 0; fi
    [ -t 0 ]
}

# Is "everything" mode on (setup.sh --everything)? A flag only, with no
# matching answer at the prompts: what it unlocks is slow or third-party
# enough that it shouldn't be one keystroke at a question about something
# else.
_pmn_heavy_wanted() { [ "$PMN_TOOLS_HEAVY" = 1 ]; }

# _pmn_confirm <required|optional> <question>
#
# Returns 0 for "install it", 1 for "leave it". Sets _PMN_ANS_* for answers
# that outlast one prompt (see their comments up top).
_pmn_confirm() {
    local kind="$1" question="$2" prompt ans

    if [ "$_PMN_ANS_QUIT" = 1 ]; then return 1; fi
    if [ "$_PMN_ANS_ALL" = 1 ]; then return 0; fi
    if [ "$kind" = optional ] && [ "$_PMN_ANS_SKIP_OPT" = 1 ]; then return 1; fi

    # Flags answer for you...
    if [ "$kind" = required ] && [ "$PMN_TOOLS_YES" = 1 ]; then return 0; fi
    if [ "$PMN_TOOLS_ALL" = 1 ]; then return 0; fi

    # ...and with no terminal there is nobody to ask.
    if [ ! -t 0 ]; then
        _pmn_note "    (not asking: no terminal. Re-run interactively, or pass --yes / --all.)"
        return 1
    fi

    if [ "$kind" = required ]; then
        prompt="  ${question} [Y/n/a/q] "
    else
        prompt="  ${question} [y/N/a/s/q] "
    fi
    while :; do
        if ! IFS= read -r -p "$prompt" ans; then
            # EOF (Ctrl-D): stop asking rather than loop on it.
            echo
            _PMN_ANS_QUIT=1
            return 1
        fi
        case "$ans" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No)    return 1 ;;
            "")              if [ "$kind" = required ]; then return 0; else return 1; fi ;;
            a|A|all)         _PMN_ANS_ALL=1; return 0 ;;
            s|S|skip)        _PMN_ANS_SKIP_OPT=1; return 1 ;;
            q|Q|quit)        _PMN_ANS_QUIT=1; return 1 ;;
            *)
                if [ "$kind" = required ]; then
                    _pmn_note "    y = install   n = not this one   a = install everything left   q = stop asking"
                else
                    _pmn_note "    y = install   n = not this one   a = install everything left   s = skip the rest of the optional tools   q = stop asking"
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Installing
# ---------------------------------------------------------------------------

# _pmn_run_shown <command...>: print the command, then run it.
_pmn_run_shown() {
    printf '    %s$ %s%s\n' "${_PMN_DIM}" "$*" "${_PMN_RESET}"
    "$@"
}

# Sudo, when the package manager needs it. A machine that is neither root
# nor has sudo can't install system packages; say so once, plainly.
_pmn_pkg_install() {
    local pkgs="$1" rc=0
    if [ "$PMN_SUDO" = "?" ] && [ "$PMN_PM" != brew ]; then
        _pmn_say "    ${_PMN_RED}cannot install:${_PMN_RESET} this needs root, and sudo isn't available."
        _pmn_say "    Run this script as root, or install by hand: $pkgs"
        return 1
    fi
    # shellcheck disable=SC2086  # $pkgs is a deliberate word list
    case "$PMN_PM" in
        apt)
            if [ "$_PMN_APT_UPDATED" = 0 ]; then
                _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} apt-get update || true
                _PMN_APT_UPDATED=1
            fi
            _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} apt-get install -y $pkgs || rc=$?
            ;;
        dnf)
            _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} dnf install -y $pkgs || rc=$?
            ;;
        pacman)
            _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} pacman -S --needed --noconfirm $pkgs || rc=$?
            ;;
        brew)
            _pmn_run_shown brew install $pkgs || rc=$?
            ;;
        *)
            return 1 ;;
    esac
    return "$rc"
}

# macOS: `xcode-select --install` returns immediately after opening a GUI
# installer, so wait for the developer directory to appear. Enter re-checks
# right away; otherwise it looks every 5 seconds.
_pmn_install_clt() {
    _pmn_run_shown xcode-select --install || true
    _pmn_say "    A dialog should have opened: click Install and wait for it to finish."
    _pmn_say "    Waiting for the tools (Enter checks now; Ctrl-C to stop waiting) ..."
    local waited=0
    until _pmn_clt_installed; do
        # Not `read -t 5` with stdin at EOF: that returns at once and would
        # spin. sleep is the wait; read only makes Enter an early re-check.
        if [ -t 0 ]; then
            IFS= read -r -t 5 _ 2>/dev/null || true
        else
            sleep 5
        fi
        waited=$((waited + 5))
        if [ "$waited" -ge 3600 ]; then
            _pmn_say "    Gave up waiting after an hour -- re-run this script once the install has finished."
            return 1
        fi
    done
    return 0
}

# Homebrew's own documented installer. It asks for your password and for a
# RETURN of its own -- those prompts are Homebrew's, and are left alone
# unless --yes was given (then NONINTERACTIVE=1 tells it not to ask).
_pmn_install_brew() {
    if ! _pmn_have curl; then
        _pmn_say "    curl not found -- see https://brew.sh for manual installation steps."
        return 1
    fi
    printf '    %s$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"%s\n' "${_PMN_DIM}" "${_PMN_RESET}"
    local rc=0
    if [ "$PMN_TOOLS_YES" = 1 ] || [ "$PMN_TOOLS_ALL" = 1 ]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || rc=$?
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || rc=$?
    fi
    # A fresh install isn't on PATH in this shell yet.
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; PMN_PM=brew; break; fi
    done
    return "$rc"
}

# wine on Arch lives in the multilib repository, which is DISABLED by
# default -- confirmed against the Arch Wiki and Arch Linux Forums, and
# the standard symptom without it is `pacman -S wine` failing with
# "error: target not found: wine", which would otherwise look like this
# script's package name is simply wrong. `pacman-conf --repo-list` is the
# reliable way to ask pacman which repositories are actually active,
# rather than grep-ing /etc/pacman.conf by hand (which a comment, or an
# include from a different file, can easily fool).
_pmn_pacman_multilib_enabled() {
    pacman-conf --repo-list 2>/dev/null | grep -qx multilib
}

# Offers to enable it -- editing /etc/pacman.conf is a bigger step than a
# normal package install, so it gets its own explicit confirmation, and
# says exactly what will change, before wine's own "Install wine?"
# question ever appears.
#
# Two ways it can be missing, tried in order: most installs ship the
# standard commented-out block, which the sed uncomments in place; some
# minimal/container base images (confirmed against an Arch distrobox
# image, which is how most people meet this path in practice) strip that
# block out of /etc/pacman.conf entirely rather than just commenting it,
# in which case the sed is a same-file no-op (a real edit either finds
# something to change or it doesn't -- there's no way to tell those apart
# except checking after) and the same two lines the Arch Wiki documents
# get appended instead. Only the first method that actually results in
# multilib being enabled runs pacman -Sy, so a real config error still
# ends in the honest "enable by hand" message rather than silently
# appending a second, conflicting [multilib] section.
_pmn_pacman_enable_multilib() {
    if [ "$PMN_SUDO" = "?" ]; then
        _pmn_say "    ${_PMN_RED}cannot enable multilib:${_PMN_RESET} editing /etc/pacman.conf needs root, and sudo isn't available."
        return 1
    fi
    _pmn_say "    wine is in Arch's multilib repository, which isn't enabled on this machine."
    _pmn_note "    That needs a one-time change to /etc/pacman.conf: uncommenting (or adding)"
    _pmn_note "      [multilib]"
    _pmn_note "      Include = /etc/pacman.d/mirrorlist"
    if ! _pmn_confirm optional "Enable the multilib repository now?"; then
        return 1
    fi
    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} sed -i \
        -e '/^#\[multilib\]/s/^#//' \
        -e '/^\[multilib\]/{n;s/^#//}' \
        /etc/pacman.conf || return 1
    if ! _pmn_pacman_multilib_enabled && ! grep -qx '\[multilib\]' /etc/pacman.conf 2>/dev/null; then
        _pmn_say "    ${_PMN_YELLOW}no [multilib] block found to uncomment${_PMN_RESET} -- appending one instead."
        _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} sh -c \
            "printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf" || return 1
    fi
    if ! _pmn_pacman_multilib_enabled; then
        _pmn_say "    ${_PMN_YELLOW}/etc/pacman.conf doesn't look like the standard layout this edits${_PMN_RESET} -- enable [multilib] by hand, then re-run."
        return 1
    fi
    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} pacman -Sy || return 1
}

# The Fedora-targeting cross toolchains that need a COPR instead of a
# Fedora-native package (see _pmn_arch_extra_notes for why): prints
# "<owner>/<project>" for the ids that need one, empty for anything else.
# One place the confirmation prompt and the install step both read from, so
# they can't drift apart. lantw44's toolchains are crosstool-NG builds of a
# full GCC+glibc (C++ included, unlike Fedora's own cross-gcc) -- see
# https://copr.fedorainfracloud.org/coprs/lantw44/.
_pmn_dnf_copr_for() {
    case "$1" in
        xc-arm64) echo "lantw44/aarch64-linux-gnu-toolchain" ;;
        xc-arm32) echo "lantw44/arm-linux-gnueabihf-toolchain" ;;
    esac
}

# Is <owner>/<project> already enabled? Asking dnf what's enabled, rather
# than guessing the generated .repo filename on disk, is the same approach
# _pmn_pacman_multilib_enabled takes with `pacman-conf --repo-list`. Best
# effort: "no" here on a dnf too old for the copr plugin just means
# _pmn_dnf_enable_copr asks again next run instead of remembering -- annoying,
# never unsafe, since enabling an already-enabled COPR is a harmless no-op.
_pmn_dnf_copr_enabled() {
    dnf -q repolist --enabled 2>/dev/null | grep -qi "copr.*${1#*/}"
}

# Offers to enable it -- adding a repository is a bigger step than a normal
# package install, so like wine's multilib prompt above, it gets its own
# explicit confirmation, separate from the "install this tool?" question
# that precedes it. COPR builds happen on Fedora's own servers (nothing
# compiles on your machine, unlike the AUR case below) but a COPR project is
# run by its owner, not reviewed by Fedora -- said plainly, once, before
# anything is added.
_pmn_dnf_enable_copr() {
    local repo="$1"
    if [ "$PMN_SUDO" = "?" ]; then
        _pmn_say "    ${_PMN_RED}cannot enable this repository:${_PMN_RESET} needs root, and sudo isn't available."
        return 1
    fi
    _pmn_say "    Fedora's own repos have no working cross compiler for this (see above) --"
    _pmn_say "    this one comes from ${repo}, a community COPR repository:"
    _pmn_note "      https://copr.fedorainfracloud.org/coprs/${repo}/"
    _pmn_note "    (built on Fedora's own servers, but not reviewed by Fedora)"
    if ! _pmn_confirm optional "Enable the ${repo} COPR repository now?"; then
        return 1
    fi
    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} dnf -y copr enable "$repo" || return 1
}

# Running a 32-bit Windows binary (the windows-x86-mingw32 preset) under
# Wine on an x64 Debian/Ubuntu host needs wine32:i386 -- a SEPARATE
# package from wine/wine64, on a SEPARATE (i386) architecture that apt
# doesn't register by default. Confirmed against Debian's own wiki and
# several Debian/Ubuntu bug reports: without this, `wine` installs and
# runs fine on 64-bit binaries, and only announces the problem the first
# time it's actually asked to run a 32-bit one -- "it looks like wine32
# is missing ... multiarch needs to be enabled first" -- which is Wine's
# own message, not this script's, and by then setup.sh already exited
# successfully long before, having had no reason to think anything was
# left to do; there's nothing to detect this from wine's own status. So
# the apt package list for wine (below) includes wine32:i386 unconditionally
# whenever wine is offered at all (x64 hosts only -- see _pmn_tools_ids),
# and this runs first to make that installable, the same two-step
# separate-confirmation shape as pacman's multilib above.
_pmn_apt_multiarch_i386_enabled() {
    dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386
}

# Is wine32:i386 actually installed? Wine itself (64-bit) runs without it and
# prints its "it looks like wine32 is missing" complaint on EVERY run, so a
# machine where wine was installed before wine32 was part of this script's
# package list would otherwise look finished: wine present -> nothing left
# to offer. Reported as "partial" (see the report loop) so it gets offered
# again, and the install is idempotent -- wine is already there, only
# wine32:i386 (and the i386 architecture it needs) is added.
_pmn_apt_wine32_installed() {
    # shellcheck disable=SC2016  # ${Status} is dpkg-query's format syntax, not ours
    dpkg-query -W -f='${Status}' wine32:i386 2>/dev/null | grep -q '^install ok installed'
}

# The mirror image of the above, and the one that bit: is wine64 installed?
# `wine` itself needs only one of wine64 and wine32, so a machine set up with
# `apt-get install wine wine32:i386` has the 32-bit wine alone -- `wine` is
# there, wine32 is there, every check above passes -- and can run no 64-bit
# Windows program: the 32-bit loader can't, and creates a 32-bit prefix even
# under WINEARCH=win64, then refuses it ("WINEARCH set to win64 but '...' is
# a 32-bit installation").
_pmn_apt_wine64_installed() {
    # shellcheck disable=SC2016  # ${Status} is dpkg-query's format syntax, not ours
    dpkg-query -W -f='${Status}' wine64 2>/dev/null | grep -q '^install ok installed'
}

_pmn_apt_enable_multiarch_i386() {
    if [ "$PMN_SUDO" = "?" ]; then
        _pmn_say "    ${_PMN_RED}cannot enable the i386 architecture:${_PMN_RESET} needs root, and sudo isn't available."
        return 1
    fi
    _pmn_say "    wine32:i386 -- needed to run 32-bit Windows binaries (the"
    _pmn_say "    windows-x86-mingw32 preset) under Wine -- needs the i386 foreign"
    _pmn_say "    architecture registered first (dpkg --add-architecture i386)."
    if ! _pmn_confirm optional "Register the i386 architecture now?"; then
        return 1
    fi
    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} dpkg --add-architecture i386 || return 1
    # A fresh update is needed here specifically: i386's package lists
    # don't exist yet even if apt-get update already ran this session for
    # the native architecture, and _pmn_pkg_install's own update only runs
    # once (_PMN_APT_UPDATED) -- set the flag after so it doesn't run again
    # right behind this one for nothing.
    _pmn_run_shown ${PMN_SUDO:+"$PMN_SUDO"} apt-get update || return 1
    _PMN_APT_UPDATED=1
}

# _pmn_install_row <row>: install one catalog row; returns its status.
_pmn_install_row() {
    local row="$1" id pkgs copr
    id="$(_pmn_field "$row" 1)"
    case "$id" in
        clt)  _pmn_install_clt; return $? ;;
        brew) _pmn_install_brew; return $? ;;
    esac
    if [ "$id" = wine ] && [ "$PMN_PM" = pacman ] && ! _pmn_pacman_multilib_enabled; then
        _pmn_pacman_enable_multilib || return 1
    fi
    if [ "$id" = wine ] && [ "$PMN_PM" = apt ] && ! _pmn_apt_multiarch_i386_enabled; then
        _pmn_apt_enable_multiarch_i386 || return 1
    fi
    if [ "$PMN_PM" = dnf ]; then
        copr="$(_pmn_dnf_copr_for "$id")"
        if [ -n "$copr" ] && ! _pmn_dnf_copr_enabled "$copr"; then
            _pmn_dnf_enable_copr "$copr" || return 1
        fi
    fi
    pkgs="$(_pmn_row_packages "$row")"
    if [ -z "$pkgs" ]; then
        _pmn_say "    ${_PMN_YELLOW}no package known for this on ${PMN_PM}${_PMN_RESET} -- install it yourself."
        return 1
    fi
    _pmn_pkg_install "$pkgs"
}

# What to tell someone whose package manager's CMake is too old (Ubuntu 22.04
# ships 3.22, Debian 11 ships 3.18). Not run automatically: which of these is
# right depends on the machine, and each one changes more than a package.
_pmn_cmake_too_old_help() {
    _pmn_say "    ${_PMN_YELLOW}CMake $1 is older than the ${PMN_CMAKE_MIN_MAJOR}.${PMN_CMAKE_MIN_MINOR} this project needs.${_PMN_RESET} Any one of:"
    _pmn_say "      pipx install cmake                      # Kitware's own wheels (pipx from your package manager)"
    _pmn_say "      sudo snap install cmake --classic        # if you use snap"
    _pmn_say "      https://cmake.org/download/               # official binary tarball"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

# Rows are collected into an array first, then looped over -- rather than
# reading a here-doc in the loop -- so a command run inside the loop (a
# package manager, sudo) can never swallow the rest of the list from stdin.
_pmn_tools_run() {
    local rows=() id row kind label why status detail pkgs missing_required=0
    local failed=""
    local pm_desc

    _pmn_tools_detect

    case "$PMN_OS" in
        linux) pm_desc="Linux ${PMN_ARCH:-?}, package manager: ${PMN_PM}" ;;
        macos) pm_desc="macOS ${PMN_ARCH:-?}, package manager: ${PMN_PM}" ;;
        *)     pm_desc="$(uname -s) (not supported by this installer)" ;;
    esac
    _pmn_say "==> Checking the tools this project builds with (${pm_desc})"

    if [ "$PMN_OS" = other ]; then
        _pmn_say "    This installer knows Linux and macOS; on Windows use breeze\\scripts\\setup.bat."
        return 0
    fi
    if [ "$PMN_OS" = linux ] && [ "$PMN_PM" = none ]; then
        _pmn_say "    ${_PMN_YELLOW}No supported package manager found${_PMN_RESET} (apt, dnf and pacman are)."
        _pmn_say "    Install these yourself: a C++ compiler, git, CMake ${PMN_CMAKE_MIN_MAJOR}.${PMN_CMAKE_MIN_MINOR}+ (and clang-format/clang-tidy, optionally)."
    fi

    for id in $(_pmn_tools_ids); do
        row="$(_pmn_row_cat "$id")"
        [ -n "$row" ] && rows+=("$row")
    done

    # ---- report ----------------------------------------------------------
    for row in ${rows[@]+"${rows[@]}"}; do
        id="$(_pmn_field "$row" 1)"; kind="$(_pmn_field "$row" 2)"; label="$(_pmn_field "$row" 3)"
        status="$(_pmn_tool_status "$id")"
        detail="${status#* }"; [ "$detail" = "$status" ] && detail=""
        case "${status%% *}" in
            ok)
                if [ -n "$detail" ]; then
                    printf '    %s[ ok ]%s  %-30s %s%s%s\n' "$_PMN_GREEN" "$_PMN_RESET" "$label" "$_PMN_DIM" "$detail" "$_PMN_RESET"
                else
                    printf '    %s[ ok ]%s  %s\n' "$_PMN_GREEN" "$_PMN_RESET" "$label"
                fi ;;
            old)
                printf '    %s[old ]%s  %-30s %s (needs %s.%s+)\n' "$_PMN_YELLOW" "$_PMN_RESET" "$label" "$detail" "$PMN_CMAKE_MIN_MAJOR" "$PMN_CMAKE_MIN_MINOR" ;;
            partial)
                printf '    %s[part]%s  %-30s %s%s%s\n' "$_PMN_YELLOW" "$_PMN_RESET" "$label" "$_PMN_DIM" "$detail" "$_PMN_RESET" ;;
            *)
                if [ "$kind" = required ]; then
                    printf '    %s[ !! ]%s  %-30s missing (required)\n' "$_PMN_RED" "$_PMN_RESET" "$label"
                else
                    printf '    %s[ -- ]%s  %-30s missing (optional)\n' "$_PMN_DIM" "$_PMN_RESET" "$label"
                fi ;;
        esac
    done
    _pmn_arch_extra_notes

    if [ "$PMN_TOOLS_CHECK" = 1 ]; then
        for row in ${rows[@]+"${rows[@]}"}; do
            id="$(_pmn_field "$row" 1)"
            if [ "$(_pmn_field "$row" 2)" = required ] && [ "$(_pmn_tool_status "$id" | cut -d' ' -f1)" != ok ]; then
                # brew is only "required" for what it installs; not a failure on its own if nothing needs it
                [ "$id" = brew ] && continue
                missing_required=1
            fi
        done
        return "$missing_required"
    fi

    # ---- offer installs, one at a time -----------------------------------
    local offered=0 skipped_optional=""
    for row in ${rows[@]+"${rows[@]}"}; do
        id="$(_pmn_field "$row" 1)"; kind="$(_pmn_field "$row" 2)"; label="$(_pmn_field "$row" 3)"
        why="$(_pmn_field "$row" 4)"

        # Re-check now: an earlier install may already have provided this
        # one (dnf's clang-tools-extra is both clang-format and clang-tidy).
        status="$(_pmn_tool_status "$id")"
        if [ "${status%% *}" = ok ]; then continue; fi

        if [ "$_PMN_ANS_QUIT" = 1 ]; then break; fi

        # Everything through Homebrew needs Homebrew first.
        if [ "$PMN_OS" = macos ] && [ "$id" != clt ] && [ "$id" != brew ] && [ "$PMN_PM" != brew ]; then
            _pmn_say
            _pmn_say "  ${_PMN_BOLD}${label}${_PMN_RESET} -- ${why}"
            _pmn_note "    skipped: needs Homebrew, which isn't installed"
            failed="$failed $id"
            continue
        fi
        if [ "$PMN_OS" = linux ] && [ "$id" != brew ]; then
            pkgs="$(_pmn_row_packages "$row")"
            if [ "$PMN_PM" = none ] || [ -z "$pkgs" ]; then
                continue    # nothing this package manager can do; already said so above
            fi
        fi

        if [ "$kind" = optional ] && ! _pmn_optional_wanted; then
            skipped_optional="${skipped_optional:+$skipped_optional, }$label"
            continue
        fi

        offered=$((offered + 1))
        _pmn_say
        _pmn_say "  ${_PMN_BOLD}${label}${_PMN_RESET} -- ${why}"
        if [ "${status%% *}" = old ]; then
            _pmn_note "    (installed: ${status#* }, but too old)"
        elif [ "${status%% *}" = partial ]; then
            _pmn_note "    (already installed, but ${status#* })"
        fi

        if _pmn_confirm "$kind" "Install ${label}?"; then
            if _pmn_install_row "$row"; then
                status="$(_pmn_tool_status "$id")"
                case "${status%% *}" in
                    ok)  _pmn_say "    ${_PMN_GREEN}installed${_PMN_RESET}" ;;
                    old) _pmn_cmake_too_old_help "${status#* }"; failed="$failed $id" ;;
                    partial) _pmn_say "    ${_PMN_YELLOW}the install finished, but ${status#* }${_PMN_RESET} -- check the output above."
                         failed="$failed $id" ;;
                    *)   _pmn_say "    ${_PMN_YELLOW}the install finished, but ${label} still isn't on PATH${_PMN_RESET} -- open a new terminal, or check the output above."
                         failed="$failed $id" ;;
                esac
            else
                _pmn_say "    ${_PMN_RED}install failed${_PMN_RESET} -- see the output above."
                failed="$failed $id"
            fi
        else
            # Declined (or quit): nothing to echo back to someone who just
            # typed it, but an optional one belongs in the closing summary.
            if [ "$kind" = optional ]; then
                skipped_optional="${skipped_optional:+$skipped_optional, }$label"
            fi
        fi
    done
    _pmn_offer_aur_arm32
    if [ "$offered" -eq 0 ] && [ -z "$skipped_optional" ] && [ "$_PMN_ANS_QUIT" != 1 ]; then
        _pmn_say "    Nothing to install."
    fi
    if [ -n "$skipped_optional" ]; then
        local install_hint="--all installs them all"
        [ "$PMN_PM" = pacman ] && install_hint="$install_hint; --everything also installs the AUR extras"
        _pmn_say
        _pmn_note "  Optional, not installed: ${skipped_optional}"
        _pmn_note "  (breeze/scripts/setup.sh, run interactively, offers each one; ${install_hint}.)"
    fi

    # ---- final verdict ---------------------------------------------------
    for row in ${rows[@]+"${rows[@]}"}; do
        id="$(_pmn_field "$row" 1)"
        if [ "$(_pmn_field "$row" 2)" = required ] && [ "$id" != brew ] \
            && [ "$(_pmn_tool_status "$id" | cut -d' ' -f1)" != ok ]; then
            missing_required=1
            _pmn_say "  ${_PMN_RED}still missing (required):${_PMN_RESET} $(_pmn_field "$row" 3)"
        fi
    done
    return "$missing_required"
}

# _pmn_tools_offer <id>: offer to install ONE catalog tool -- for callers that
# find out mid-way that they need it (setup.sh, when there is no pinned Ninja
# for this machine). Same prompt, same command display, same rules.
_pmn_tools_offer() {
    local id="$1" row status
    _pmn_tools_detect
    row="$(_pmn_row_cat "$id")"
    [ -n "$row" ] || return 1
    status="$(_pmn_tool_status "$id")"
    [ "${status%% *}" = ok ] && return 0
    if [ -z "$(_pmn_row_packages "$row")" ] || [ "$PMN_PM" = none ]; then
        _pmn_say "    Install $(_pmn_field "$row" 3) yourself: $(_pmn_field "$row" 4)."
        return 1
    fi
    _pmn_say
    _pmn_say "  ${_PMN_BOLD}$(_pmn_field "$row" 3)${_PMN_RESET} -- $(_pmn_field "$row" 4)"
    if _pmn_confirm "$(_pmn_field "$row" 2)" "Install $(_pmn_field "$row" 3)?"; then
        if ! _pmn_install_row "$row"; then
            _pmn_say "    ${_PMN_RED}install failed${_PMN_RESET} -- see the output above."
            return 1
        fi
        if [ "$(_pmn_tool_status "$id" | cut -d' ' -f1)" = ok ]; then
            _pmn_say "    ${_PMN_GREEN}installed${_PMN_RESET}"
            return 0
        fi
        _pmn_say "    ${_PMN_YELLOW}the install finished, but $(_pmn_field "$row" 3) still isn't on PATH${_PMN_RESET} -- open a new terminal, or check the output above."
        return 1
    fi
    return 1
}
