# CMakeTemplate

A C++20 project template for CMake 3.25+ that builds the same way on Linux, macOS and Windows.

- **Adding code means adding a folder.** A module is a directory under `source/` whose
  `CMakeLists.txt` is one or two lines long. The root `CMakeLists.txt` is never edited.
- **The template is one folder.** `breeze/` holds everything that makes it work: the build system,
  toolchains, scripts and these docs. `project/` holds this project's own settings, and `source/`,
  `vendor/` and `out/` are yours, at the root. Updating the template means replacing `breeze/`.
- **Sixteen targets, one preset each.** Linux (x64, arm64, arm32 × GCC, Clang), macOS (arm64, x64),
  Windows (x64, arm64 × MSVC, clang-cl, Clang; x64 and x86 MinGW-w64). Every target has its own
  toolchain file and its own build directory, so switching targets never rebuilds anything.
- **One setup script** checks your machine and offers to install what is missing, one tool at a
  time, nothing without your yes.
- **A working demo** to copy from: the shared library `core_lib` (with a piece of it, `core_farewell`, in an
  objects module of its own), the executables `hello_exe` and
  `farewell_exe`, a vendored header-only dependency (`tiny_ansi`), a vendored CMake dependency
  (`tiny_case`) and `fmt`, fetched from Git.

**Part 1, using the template:** [Requirements](#requirements) · [Quick start](#quick-start) ·
[Choosing a target](#choosing-a-target) · [Everyday commands](#everyday-commands) ·
[Adding code](#adding-code) · [Settings](#settings) · [Making it yours](#making-it-yours) ·
[Updating the template](#updating-the-template) · [Troubleshooting](#troubleshooting)

**Part 2, how it works:** [Layout](#repository-layout) · [The settings file](#the-settings-file) ·
[Modules](#modules) · [Dependencies](#dependencies) · [Targets and toolchains](#targets-and-toolchains) ·
[Setup internals](#setup-internals) · [Script internals](#script-internals) ·
[Style and tooling](#style-and-tooling) · [Embedding](#embedding) ·
[Verification status](#verification-status)

---

# Part 1: Using the template

## Requirements

- **Required:** Git, CMake 3.25 or newer, and a C++20 compiler (GCC, Clang, MSVC or MinGW-w64).
- **Optional, each only for what uses it:** Clang, clang-format and clang-tidy (`refactor` and the
  pre-commit hook), cross compilers, MinGW-w64, `qemu-user` and `wine` (to run cross-built
  programs), Doxygen.
- **Fetched for you** into `.cache/tools/`: Ninja 1.13.2 and Doxygen 1.16.1, pinned so every machine
  builds with the same versions. A Ninja already on `PATH` is the fallback; the project builds
  without Doxygen.
- Setup installs tools through apt, dnf and pacman (Linux), Homebrew (macOS) and winget (Windows).
  On anything else it reports what is missing and leaves the installing to you.

## Quick start

```sh
breeze/scripts/setup.sh                  # once per clone; asks before installing anything
breeze/scripts/build.sh                  # configure and build (Release)
breeze/scripts/run.sh hello_exe World    # Hello, World! (from demo_core)
```

On Windows use `breeze\scripts\setup.bat`, `breeze\scripts\build.bat` and `breeze\scripts\run.bat hello_exe World`, from
`cmd` or PowerShell.

To build for a specific target, name its preset: `breeze/scripts/build.sh --preset linux-x64-clang`. `run`
then follows the build you made last, or takes `--preset` too.

## Choosing a target

A target is a preset named `<os>-<arch>-<compiler>`. `breeze/scripts/build.sh --list-presets` shows the ones
your OS offers. Without `--preset` the first compiler CMake finds is used and the build goes to
`out/build/default/`.

| Presets | Build | Needs |
|---|---|---|
| `linux-x64-gcc` `linux-x64-clang` `linux-arm64-gcc` `linux-arm64-clang` `linux-arm32-gcc` `linux-arm32-clang` | Linux on x86-64, AArch64, 32-bit ARM | On matching hardware, just the compiler. Otherwise a cross compiler for that architecture; the Clang presets also need Clang. |
| `macos-arm64-clang` `macos-x64-clang` | macOS on Apple Silicon, Intel | Xcode Command Line Tools. Either Mac builds both; x64 programs run on Apple Silicon under Rosetta 2. |
| `windows-x64-msvc` `windows-arm64-msvc` | Windows, MSVC | Visual Studio or Build Tools with the C++ workload. ARM64 also needs the ARM64 build tools component; from an x64 machine that is a cross build (`breeze\scripts\setup.bat` offers to add it). |
| `windows-x64-clang-cl` `windows-arm64-clang-cl` | Windows, clang-cl (MSVC ABI) | The above plus clang-cl: LLVM, or Visual Studio's Clang component. |
| `windows-x64-clang` `windows-arm64-clang` | Windows, MSYS2 Clang (MinGW ABI) | MSYS2's CLANG64 (x64) or CLANGARM64 (ARM64) Clang package. MSYS2 has CLANGARM64 only on ARM64 Windows, so `windows-arm64-clang` needs such a machine; from x64 use the ARM64 MSVC or clang-cl presets. |
| `windows-x64-mingw64` `windows-x86-mingw32` | Windows, MinGW-w64 GCC | MSYS2 with MinGW-w64 GCC. Also cross-builds from Linux. |

**Cross builds.** A Linux preset for another architecture compiles with the matching
`<triplet>-g++` (`aarch64-linux-gnu`, `arm-linux-gnueabihf`, `x86_64-linux-gnu`); the MinGW presets
also cross-build from Linux. Setup installs these where your package manager has them (see
[What setup can install](#what-setup-can-install)). If `qemu-user` (Linux targets) or `wine`
(Windows targets) is installed when you configure, `breeze/scripts/run` and `ctest` use it to run the
result.

**Windows ARM64 from an x64 machine** is a cross build too: `windows-arm64-msvc` and
`windows-arm64-clang-cl` compile with Visual Studio's x64-hosted ARM64 tools (`vcvarsall x64_arm64`),
which need the ARM64 build tools component, and the programs cannot run on the build machine.

**Windows environments.** MSVC and clang-cl only work inside a Visual Studio developer environment,
and MSYS2's compilers only with their folder on `PATH`. `breeze\scripts\build.bat` enters the right one for
the preset by itself, for that run only, so no "Native Tools Command Prompt" or MSYS2 shell is
needed; `PMN_NO_ENV=1` turns it off ([details](#windows-environments)). Plain `cmake --preset ...`
and IDEs don't do this: start them from the matching prompt.

## Everyday commands

Every script exists as `.sh` and `.bat` with the same options, answers `-h` / `--help`, and works
from any directory in the repository. `--preset NAME` (or `--preset=NAME`) must come first.

| Script | Usage | Does |
|---|---|---|
| `setup` | `[--yes] [--all] [--everything] [--check] [--skip-tools]` | Checks and installs tools, fetches pinned Ninja and Doxygen, activates the pre-commit hook. |
| `build` | `[--preset NAME] [BUILD_TYPE] [CMAKE_ARGS…]`<br>`--list-presets` | Configures and builds into `out/build/<preset>`. `BUILD_TYPE` is `Debug`, `Release` (default), `RelWithDebInfo` or `MinSizeRel`; further arguments go to CMake as they are, e.g. `-DBUILD_TESTS=ON`. |
| `run` | `[--preset NAME] TARGET [ARGS…]` | Runs an executable by CMake target name; without a target it lists them. Cross-built programs run under qemu or wine when available. |
| `install` | `[--preset NAME] [BUILD_TYPE]` | Installs this project's targets to `out/install/<preset>/{bin,lib}`. |
| `docs` | `[--preset NAME] [MODULE]` | Builds the Doxygen docs of every module, or one, into `out/docs/`. |
| `refactor` | `[PATH]` | Runs clang-format, then clang-tidy `--fix` (which needs a previous build for its compile database), over `source/` and `c-api/`, or just `PATH`. Review with `git diff`. |

`run`, `install` and `docs` act on the build made last unless you pass `--preset`; `BUILD_DIR`
selects an exact directory instead. The build type is not part of the directory name, so changing it
within a preset reconfigures that directory.

**Setup flags.** `--yes` installs the required tools without asking (for CI), `--all` the optional
ones too, `--everything` also the third-party extras (today: Arch's prebuilt 32-bit ARM toolchain
from the AUR), `--check` only reports and exits 1 if a required tool is missing, `--skip-tools` goes
straight to the downloads. At each question: `y` installs, `n` skips that tool, `a` accepts everything
left, `s` skips the remaining optional tools, `q` stops asking. With no terminal and no flag nothing
is installed.

**CMake directly.**

```sh
cmake --preset linux-x64-gcc
cmake --build --preset linux-x64-gcc
ctest --test-dir out/build/linux-x64-gcc        # tests need -DBUILD_TESTS=ON
```

IDEs with preset support (CLion, VS Code, Visual Studio) list the presets for your OS; personal ones
go in `CMakeUserPresets.json`. A bare `-DDIST_TARGET=…` only labels a build, it does not choose a
compiler, and a label that disagrees with the compiler stops the configure: pick targets with
presets.

## Adding code

Create a directory with a `CMakeLists.txt`; the next build finds it.

```cmake
# source/MyLib/CMakeLists.txt      library: sources in src/, headers in include/
add_lib_module(my_lib TYPE SHARED DEPENDS fmt::fmt)

# source/MyPiece/CMakeLists.txt    objects: compiled, no library of its own (a piece of one)
add_objects_module(my_piece)     # taken in by naming it: add_lib_module(my_lib DEPENDS my_piece)

# source/MyApp/CMakeLists.txt      executable: *.cpp in the module
add_exe_module(my_app DEPENDS my_lib)

# source/tests/my_test/CMakeLists.txt        built with -DBUILD_TESTS=ON, registered with CTest
add_test_module(my_test DEPENDS my_lib)

# source/examples/my_example/CMakeLists.txt  built with -DBUILD_EXAMPLES=ON
add_example_module(my_example DEPENDS my_lib)
```

Options: `OUTPUT_NAME <file name>` (for an objects module, which has no file, only the name `MODULE_NAME`
carries), `DEPENDS <targets>`, `EXTRA_SOURCES <files>`, `NO_DOCS`. Third-party
code comes in three ways, called from the CMakeLists of the module that needs it:

```cmake
add_vendor_header_only(tiny_ansi)       # vendor/tiny_ansi/include, header-only
add_vendor_subdirectory(tiny_case)      # vendor/tiny_case/CMakeLists.txt
add_dependency(fmt                      # an installed copy if new enough, else fetched
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git  GIT_TAG 12.1.0
    FIND_PACKAGE_ARGS 12 NAMES fmt)
```

What one module declares, every module can use: `source/CoreFarewell` depends on the `fmt::fmt` that
`source/Core` declares, whether fmt was fetched or an installed copy was found.

Every module also gets Doxygen docs (`NO_DOCS` opts out; a `README.md` in the module's directory
becomes its main page).

## Settings

Pass options to `build` as CMake arguments, e.g. `breeze/scripts/build.sh -DBUILD_TESTS=ON`.

| Option | Default | Effect |
|---|---|---|
| `BUILD_TESTS`, `BUILD_EXAMPLES` | OFF | Build the modules under `source/tests` and `source/examples`. |
| `INSTALL_TESTS`, `INSTALL_EXAMPLES` | OFF | Also install them (implies the matching `BUILD_` option). |
| `BUILD_SHARED_LIBS` | OFF | Library type for modules that don't say `TYPE`. |
| `ENABLE_DOXYGEN` | ON | Per-module documentation; `-DDOXYGEN_<TAG>=…` sets any Doxyfile tag. |
| `PMN_MINGW_STATIC_RUNTIME` | OFF | MinGW: link the GCC runtime into executables instead of shipping its DLLs. Unsafe when an executable uses a shared module that passes STL types across its interface. |

The project's own settings (its name, version, languages and C++ standard, `PROJECT_CODE_NAME`,
`DEFAULT_BUILD_TYPE`, `OUT_DIR` and the directories under it) live in `project/Configuration.cmake`;
the cache variables among them can also be overridden with `-D`.

## Making it yours

1. In `project/Configuration.cmake` set `PROJECT_TITLE`, `PROJECT_VERSION_NUMBER`, `PROJECT_SUMMARY`,
   `PROJECT_LANGUAGES` and `PROJECT_CXX_STANDARD` (the arguments of `project()` and the C++ standard),
   `PROJECT_CODE_NAME` (it becomes the `PROJECT_NAME_CODE` compile definition and the install
   component) and `DEFAULT_BUILD_TYPE`.
2. Delete the demo modules in `source/` and `vendor/` and add your own.
3. Replace the root `README.md` with the project's own (Doxygen uses it as the main page).
4. Run `breeze/scripts/setup`.

Nothing in `breeze/` needs an edit. The root `CMakeLists.txt` and `CMakePresets.json` are yours to
extend (project-wide CMake of your own, or presets that `inherit` from the template's) and need
nothing to get started.

## Updating the template

The template is the `breeze/` folder and nothing else; no file of the project's lives in it. To
update, replace the folder with the new version's and run `breeze/scripts/setup` again (it points
git's `core.hooksPath` at `breeze/githooks` and re-checks your tools).

| The project's (an update never touches them) | The template's (replaced as a whole) |
|---|---|
| `project/`, `source/`, `vendor/`, `c-api/`; the root `CMakeLists.txt`, `CMakePresets.json` and `README.md` | `breeze/` |

Four kinds of file sit at the root, outside `breeze/`, because the tools that read them look there: the
dot files (`.clang-format`, `.clang-tidy` and `c-api/.clang-tidy`, `.editorconfig`, `.gitattributes`)
and `.gitignore`, whose marked block every configure rewrites. A new template version may change
them: compare them with the new copies. A new version may also read a setting your
`project/Configuration.cmake` doesn't have yet; the configure then stops and names it, and the new
version's own `project/Configuration.cmake` shows its default.

**With the `breeze` CLI** the update is `breeze sdk update` (what is available), `breeze sdk upgrade` (the newest
version of your major version) or `breeze sdk migrate <version>`: it replaces `breeze/` for you (keeping the old one in
`.breeze/backup/`), adds the settings the new version has, and moves a project in the old flat layout to this one. The
SDK's version is `breeze/VERSION`, one line, and a release of the template is a tag (`v1.2.0`) whose `breeze/VERSION`
says the same.

**Moving a project that has the old flat layout** (`cmake/`, `scripts/` and `Configuration.cmake` at the
root): put in `breeze/`, `project/` and the new root `CMakeLists.txt`, `CMakePresets.json` and
`README.md`, and delete the old `cmake/`, `scripts/`, `.githooks/`, `StyleGuide.md` and
`Configuration.cmake`. Carry your values over into `project/Configuration.cmake`: from the old
`Configuration.cmake` (`PROJECT_CODE_NAME`, `DEFAULT_BUILD_TYPE`, any output path you changed) and from
the old `CMakeLists.txt` (the `project()` arguments and the C++ standard). Run `breeze/scripts/setup`
once, which moves `core.hooksPath` from `.githooks` to `breeze/githooks`, and delete `out/build/`: the
old build directories point at files that are gone.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Windows: CMake says `cl` is missing or targets the wrong architecture | CMake ran outside the right Visual Studio developer prompt. Use `breeze\scripts\build.bat`, or open the matching prompt, then delete the build directory. |
| Windows: a MinGW or `-clang` preset can't find its compiler | MSYS2's toolchain folder isn't on `PATH`. `breeze\scripts\build.bat` adds it; set `MSYS2_ROOT` if MSYS2 isn't in `<system drive>\msys64`. |
| Windows: `cannot open msvcrt.lib`, `could not open 'msvcrtd.lib'`, or an x64 `cl` used for an ARM64 preset | The Visual Studio component for that target isn't installed. For ARM64 it is "MSVC … C++ ARM64/ARM64EC build tools (Latest)", which an x64 machine needs to cross-compile. `breeze\scripts\setup.bat` offers to add it, and `breeze\scripts\build.bat` stops with this explanation before CMake runs. |
| `windows-arm64-clang` on an x64 machine says it needs MSYS2's CLANGARM64 | MSYS2 provides CLANGARM64 only on ARM64 Windows. Build ARM64 from x64 with `windows-arm64-msvc` or `windows-arm64-clang-cl`. |
| `linux-arm32-*` fails with `invalid -march= option` or `Scrt1.o: file not recognized` | The cross compiler, binutils and C library come from different package sets. `breeze/scripts/setup.sh` reports this as `[part]`; on Arch x64 it replaces them with a matching prebuilt set. |
| A cross build stops with `Could NOT find X11` (or OpenGL, ALSA, …), though the host has it | Cross builds look only in the target's root, which has the C/C++ runtime and nothing else; the host's libraries are for the wrong architecture. Give the build a target sysroot: a root filesystem for the target with those libraries in `.cache/sysroots/linux-<arch>`, or `-DCMAKE_SYSROOT=<dir>`. See [Cross builds and system libraries](#cross-builds-and-system-libraries). |
| `breeze/scripts/run` can't run a cross-built program | No emulator was installed when the build directory was configured. Install `qemu-user` or `wine` and run `breeze/scripts/build` again. |
| wine complains about its prefix | Delete `.cache/wine/`; it is rebuilt on the next run. |
| "No pinned Ninja / Doxygen binary is configured for this machine" | Pinned downloads exist for x64 and arm64 on Windows, Linux and macOS (Doxygen: x64 Linux and Windows, and macOS). A 32-bit `cmake.exe` on 64-bit Windows looks the same. Use 64-bit CMake, or put Ninja / Doxygen on `PATH` (`-DDOXYGEN_EXECUTABLE=…`). |
| `DIST_TARGET` mismatch error | `-DDIST_TARGET=…` disagrees with the compiler CMake chose. Use `--preset`, or drop the option. |
| `linux-arm32-gcc` looks for a cross compiler on a 32-bit userland running on a 64-bit ARM kernel | `uname -m` reports aarch64 there. Pass `-DCMAKE_CXX_COMPILER=g++`. |
| The pre-commit hook rejects a commit | clang-format or clang-tidy found problems in staged C/C++ files. Run `breeze/scripts/refactor` and review the diff. |

---

# Part 2: How it works

## Repository layout

```
CMakeLists.txt             the project's entry point: project(), then breeze/ (never edited)
CMakePresets.json          includes breeze/CMakePresets.json; the project's own presets go here
README.md                  the project's own
project/
  Configuration.cmake      the project's settings: identity, output paths. One source of truth
breeze/                    the template: replace this folder to update it
  README.md  StyleGuide.md
  VERSION                  the SDK's version, one line (the `breeze` CLI reads it)
  CMakePresets.json        16 configure + 16 build presets, plus hidden base presets
  cmake/
    Breeze.cmake           the build system: options, output dirs, module discovery, install rules
    TargetSelection.cmake  DIST_TARGET -> PLATFORM, ARCHITECTURE, COMPILER_ID
    GitignoreSync.cmake    keeps the generated block of .gitignore current
    BuildHelpers.cmake     module macros, output dirs, RPATH, runtime DLLs, manifest
    Dependencies.cmake     add_vendor_header_only, add_vendor_subdirectory, add_dependency
    Documentation.cmake    per-module Doxygen targets            (+ DoxygenPin, FetchDoxygen)
    NinjaPin.cmake         pinned Ninja                          (+ FetchNinja)
    HostArch.cmake         machine architecture -> x64 / arm64 / arm32
    PrintConfig.cmake      script mode: print project/Configuration.cmake values
    BuildDir.cmake         script mode: which build directory a script uses
    CopyRuntimeDlls.cmake  post-build copy of runtime DLLs
    toolchains/            one file per target, plus _common.cmake
  scripts/                 setup build run install docs refactor, each .sh + .bat
                           helpers: _common.sh  _tools.sh  _tools.ps1  _winenv.bat
  githooks/pre-commit      clang-format + clang-tidy on staged files
source/                    Core/ (core_lib)  CoreFarewell/ (core_farewell, objects)  HelloApp/  FarewellApp/
                           [tests/  examples/]
vendor/                    tiny_case/ (CMake project)  tiny_ansi/ (header-only)
c-api/                     .clang-tidy for a C API surface
.clang-format  .clang-tidy  .editorconfig  .gitattributes  .gitignore
```

Generated, git-ignored: `out/` (`build/<preset>/`, `install/<target>/`, `docs/`, `dist/` reserved)
and `.cache/` (`tools/`, `wine/`, `sysroots/`).

## The settings file

`project/Configuration.cmake` defines the project's identity and every output path. The output
settings are cache variables, so `-D` overrides any; the identity values are plain variables, because
the root `CMakeLists.txt` passes them to `project()`. The scripts never duplicate a value: they read
it through `cmake -P` helpers.

| Variable | Default | Meaning |
|---|---|---|
| `PROJECT_TITLE` `PROJECT_VERSION_NUMBER` `PROJECT_SUMMARY` `PROJECT_LANGUAGES` | `DemoApp` `0.1.0` … `CXX` | The name, `VERSION`, `DESCRIPTION` and `LANGUAGES` of `project()`. |
| `PROJECT_CXX_STANDARD` | `20` | `CMAKE_CXX_STANDARD`; the standard is required and compiler extensions are off. |
| `PROJECT_CODE_NAME` | `demo` | Compile definition `PROJECT_NAME_CODE`; the `cmake --install` component. |
| `DEFAULT_BUILD_TYPE` | `Release` | Used by CMake and the scripts when no type is given. |
| `OUT_DIR` | `<source>/out` | Root of everything generated. |
| `BUILD_OUTPUT_DIR` `INSTALL_OUTPUT_DIR` `DOCS_OUTPUT_DIR` `DIST_OUTPUT_DIR` | `OUT_DIR/build` `/install` `/docs` `/dist` | One build directory per preset, one install directory per `DIST_TARGET`; `dist` is reserved. |
| `TOOLCACHE_DIR` | `<source>/.cache/tools` | Pinned Ninja and Doxygen. |
| `RUNTIME_OUTPUT_SUBDIR` `LIBRARY_OUTPUT_SUBDIR` `ARCHIVE_OUTPUT_SUBDIR` | `bin` `bin` `lib` | Layout inside a build or install tree. |
| `COMPILE_COMMANDS_DESTINATION` | `<source>/compile_commands.json` | Copy of the compile database for clangd and clang-tidy, refreshed after each build. |

`DIST_TARGET`, `PLATFORM`, `ARCHITECTURE` and `COMPILER_ID` are not settings: the template derives them
(`breeze/cmake/TargetSelection.cmake`, see [Target selection](#target-selection)).

- **Script mode.** `cmake "-DPRINT_VARS=A;B" -P breeze/cmake/PrintConfig.cmake` prints `-- A=value` lines.
  `cmake [-DPMN_NAME=<preset|default>] [-DPMN_RECORD=ON] -P breeze/cmake/BuildDir.cmake` prints
  `-- BUILD_DIR=…` (or `-- ERROR=…`) and, with `PMN_RECORD`, remembers the choice in
  `out/build/.last`. A plain `cmake -P` script can include the settings file because it holds
  settings only: nothing in it needs a compiler or writes a file. Target selection and the
  `.gitignore` sync are the template's, and only a real configure runs them.
- **`.gitignore`.** A marked block is regenerated on every real configure from the output paths, so
  moving `OUT_DIR` updates it. The rest of the file is never touched.

## Modules

- **Discovery.** Every `source/<dir>/`, `source/tests/<dir>/` and `source/examples/<dir>/` that
  contains a `CMakeLists.txt` is added, with `CONFIGURE_DEPENDS`, so adding or removing a module
  reconfigures by itself.
- **Macros** (`breeze/cmake/BuildHelpers.cmake`). `add_lib_module` (`add_static_lib_module` and
  `add_shared_lib_module` are shorthands for its `TYPE`), `add_objects_module`, `add_exe_module`,
  `add_test_module`, `add_example_module`.

| Macro | Sources (recursive globs) | Output | Notes |
|---|---|---|---|
| `add_lib_module` | `src/*.cpp`, `include/*.h(pp)` | shared: `bin/`, static: `lib/` | `include/` is public. Without `TYPE`, `BUILD_SHARED_LIBS` decides. |
| `add_objects_module` | `src/*.cpp`, `include/*.h(pp)` | nothing of its own: the objects go into whatever names it in `DEPENDS` | `include/` is public. See "Objects modules" below. |
| `add_exe_module` | `*.cpp`, `include/*.h(pp)` | `bin/` | |
| `add_test_module` | same | `bin/tests/` | Registered with CTest and `all_tests`; `EXCLUDE_FROM_ALL` unless `BUILD_TESTS`. |
| `add_example_module` | same | `bin/examples/` | Same, with `BUILD_EXAMPLES`. |

- **What each module target gets.** The compile definitions `MODULE_NAME` (its output name; for an objects
  module the `OUTPUT_NAME` it was given),
  `PROJECT_NAME`, `PROJECT_NAME_CODE`, `PROJECT_VER` and, in Debug, `DEBUG`; warnings (`/W4
  /permissive-` on MSVC, `-Wall -Wextra -Wpedantic` elsewhere); its `DEPENDS` linked `PRIVATE` (objects
  modules, below, are the exception for libraries); an
  RPATH of `$ORIGIN` (`$ORIGIN/..` for tests and examples), which becomes `@loader_path` for Mach-O
  in one place, `_apply_rpath`; and a Doxygen target unless `NO_DOCS`. Project-wide: C++20 without
  extensions, position-independent code, `CMAKE_BUILD_WITH_INSTALL_RPATH` off Windows.
- **Objects modules.** `add_objects_module` compiles a directory to object files and stops there: no
  archive, no DLL, nothing in `bin/` or `lib/`. Name it in the `DEPENDS` of a library, an executable, a
  test, an example or another objects module, and its objects become part of that target. That makes it
  the way to split a big library into pieces: each piece is a module of its own, with its own `include/`,
  and what remains of the library is a line naming them.

  ```cmake
  # source/CoreMath/CMakeLists.txt
  add_objects_module(core_math OUTPUT_NAME "core")
  # source/CoreIo/CMakeLists.txt
  add_objects_module(core_io OUTPUT_NAME "core" DEPENDS core_math)
  # source/Core/CMakeLists.txt        the library: its own sources, plus the pieces
  add_lib_module(core_lib TYPE SHARED OUTPUT_NAME "core" DEPENDS core_io)
  ```

  - **Name the direct pieces only.** `core_lib` above gets `core_math` too, because `core_io` needs it:
    CMake links an object library's objects into the target that names it and no further, so the
    template follows the objects modules behind the ones you name (`_resolve_object_modules`, run once
    all modules are discovered, so directory order doesn't matter). Cycles stop the configure.
  - **Headers.** A piece's `include/` is public, and a library passes its pieces' headers on: whoever
    depends on `core_lib` sees `core_math`'s and `core_io`'s headers. Those consumers must not name the
    pieces again, which would link a second copy of the objects into them (two copies of the library's
    state, when it is shared). An executable takes pieces privately. Keep a piece's private headers in
    `src/`.
  - **`OUTPUT_NAME`** is only what `MODULE_NAME` carries, so that the pieces of one library all identify
    as it. What a piece links itself, a static library for instance, is reached at the final link.
  - **What they are not.** Not installed, not run, not in the manifest; always position-independent,
    because they may end up in a shared library. Tests and examples can name a piece to test it without
    the rest of the library. `source/CoreFarewell` is the demo: `core_lib` takes it in, and
    `farewell_exe` finds `core/Farewell.hpp` through `core_lib` alone.
- **Manifest.** Each configure writes `module_manifest-<CONFIG>.txt` into the build directory, one
  `target=path` line per executable; `breeze/scripts/run` resolves target names through it.
- **Runtime DLLs (Windows).** Shared modules an executable depends on are copied next to it after
  the build (`CopyRuntimeDlls.cmake`: `cmake -E copy_if_different` fails on the empty list that
  `$<TARGET_RUNTIME_DLLS:…>` is for most targets). For
  MinGW the GCC runtime (`libgcc_s_*-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll`) is located
  through the compiler and copied the same way, and installed beside the executables.
  `PMN_MINGW_STATIC_RUNTIME=ON` links executables statically instead; that is unsafe when they use a
  shared module whose interface passes STL types (separate heaps and unwinders), hence off by
  default.
- **Install.** Targets are tagged with the component `PROJECT_CODE_NAME` and go to
  `out/install/<DIST_TARGET>/{bin,lib}` (tests and examples under `bin/tests`, `lib/tests`, … when
  `INSTALL_TESTS` / `INSTALL_EXAMPLES`). `breeze/scripts/install` always passes `--component`, which keeps
  the `install()` rules of fetched or vendored dependencies out; a bare `cmake --install` would run
  them too.
- **Docs.** A `docs_<target>` target per module plus an aggregate `docs`, built into
  `out/docs/<target>/html/` with `out/docs/index.html` linking them. Any Doxyfile tag can be set
  as `DOXYGEN_<TAG>`. Without a usable Doxygen, or with `ENABLE_DOXYGEN=OFF`, `breeze/scripts/docs` does nothing and says
  why; `-DDOXYGEN_PINNED_VERSION=…` replaces the pinned version.

## Dependencies

`breeze/cmake/Dependencies.cmake` offers `add_vendor_header_only(NAME [INCLUDE_DIR dir])` (an INTERFACE
target over `vendor/<name>/include`), `add_vendor_subdirectory(SUBDIR)` (a source drop, submodule or
subtree with its own `CMakeLists.txt`) and `add_dependency(NAME <FetchContent_Declare args>)`
(`find_package` first when `FIND_PACKAGE_ARGS` is given, a fetch otherwise). All three keep the
dependency's warnings out of your build (`SYSTEM`) and its targets out of `compile_commands.json`,
and all are no-ops when repeated for the same name, so two modules may ask for the same dependency.
The targets are usable from every module, wherever the call was made: an installed copy's imported
targets are directory-scoped by default, so `add_dependency` makes them global for the call
(`CMAKE_FIND_PACKAGE_TARGETS_GLOBAL`), and a sibling module's `DEPENDS fmt::fmt` finds them.
Always give `FIND_PACKAGE_ARGS` a minimum version: without one any installed copy beats the pinned
tag. A dependency's own options are set (`set(<OPTION> … CACHE …)`) before the call;
`source/Core/CMakeLists.txt` is the commented example. In cross builds `find_package` only looks in
the target's root, so a host's `libfmt` is never picked up -- and neither is anything the target's
root lacks, which is what a target sysroot is for (see
[Cross builds and system libraries](#cross-builds-and-system-libraries)).

## Targets and toolchains

### Target selection

`DIST_TARGET` is the one label of a build, `<platform>-<arch>-<compiler>`; `PLATFORM`,
`ARCHITECTURE` (`x64`, `arm64`, `arm32`, `x86`) and `COMPILER_ID` (`gcc`, `clang`, `msvc`,
`clang-cl`, `mingw64`, `mingw32`) follow from it.

- A **toolchain file** (`breeze/cmake/toolchains/<target>.cmake`, three lines each) declares it with
  `pmn_toolchain_target(<target>)` and calls one family macro: `pmn_linux_toolchain(arch gcc|clang)`,
  `pmn_macos_toolchain(arch)`, `pmn_msvc_toolchain(arch)`, `pmn_clang_cl_toolchain(arch)`,
  `pmn_msys_clang_toolchain()`, `pmn_mingw_toolchain(arch)`. An explicit `-DDIST_TARGET` must agree
  with the toolchain's.
- **Without a toolchain**, `TargetSelection.cmake` detects the target from the compiler CMake found.
  Linux: the machine's architecture (`HostArch.cmake`) and the compiler ID. macOS:
  `CMAKE_OSX_ARCHITECTURES`, else `CMAKE_SYSTEM_PROCESSOR`; several architectures (a universal
  binary) is an error. Windows: MSVC and clang-cl by `CMAKE_CXX_COMPILER_ARCHITECTURE_ID`, GNU-style
  Clang by the host architecture, GCC as MinGW by pointer size (there is no ARM MinGW target:
  MinGW-w64's GCC has no ARM64 Windows backend).
- An explicit `-DDIST_TARGET` is **cross-checked** against that detection, and a disagreement stops
  the configure with the toolchain file or preset to use. An undetectable architecture also stops
  it, with the list of valid values.
- **Presets** (`breeze/CMakePresets.json`, version 6, included by the root `CMakePresets.json`). A hidden `base` (Ninja, `out/build/${presetName}`)
  and host-OS bases with `condition`s (`base-linux`, `base-macos`, `base-windows`, `base-mingw` for
  Windows or Linux hosts) sit under 16 visible configure presets and 16 build presets with the same
  names. There are no test presets.

### Linux

`pmn_linux_toolchain` decides by comparing the requested architecture with the machine's.

- **Native** uses the ordinary `g++` / `clang++`. **Cross** uses `<triplet>-g++` /
  `<triplet>-gcc`, resolved to absolute paths so every `try_compile` agrees; a missing compiler stops
  with the install hint. A compiler passed with `-DCMAKE_CXX_COMPILER` beats the toolchain's; a stray
  `CXX` environment variable does not. A 32-bit userland on a 64-bit ARM kernel reports `aarch64`, so
  it needs `-DCMAKE_CXX_COMPILER=g++`.
- **Cross mechanics** (`pmn_cross_target`): `CMAKE_SYSTEM_NAME` / `PROCESSOR` are set, programs come
  from the host, and libraries, headers and packages only from the target sysroot (if there is one, see below) and
  `/usr/<triplet>`.
- **Emulator** (`pmn_cross_emulator`): `qemu-<arch> -L <root>` for Linux targets, `wine64` /
  `wine` for MinGW. It is stored as the cache entry `CMAKE_CROSSCOMPILING_EMULATOR` once found, so an
  emulator installed later is picked up by the next configure and a stored choice stays until you
  change the entry or delete the build directory. `breeze/scripts/run` and CTest read it from there.
- **Clang** cross builds use `clang++ --target=<triple>` with the cross g++'s libstdc++ and linker.
  When that g++ reports a real sysroot (dnf's COPR toolchains, ARM's own), Clang also gets
  `--sysroot` and `--gcc-toolchain=/usr`; flat layouts (Debian's `/usr/<triplet>`, pacman's) need
  neither.
- **Checks.** The toolchain asks the installed cross g++ about itself instead of trusting a
  convention, because a cross compiler is only as good as the binutils and C library installed
  beside it. Each check is a warning with the likely cause, printed once, and configure carries on:
  - a sysroot that `-print-sysroot` reports but that isn't on disk is dropped (Clang would otherwise
    fall back to the host's crt files: `Scrt1.o: file not recognized`);
  - Clang's `--target` is the triple `-dumpmachine` reports when it is the same architecture:
    ARM's own GCC is `arm-none-linux-gnueabihf`, and Clang finds its libraries only under that
    name;
  - `-print-prog-name=as` returning a bare `as` means GCC found no assembler for its target and will
    run the host's (`invalid -march= option`).
- **Idempotence.** CMake reads a toolchain file again for every scope that needs it (`project()`,
  each enabled language, `try_compile`), so everything here must be cheap and leave the same result
  when repeated; flags appended to `*_FLAGS_INIT` are added only if absent.

#### Cross builds and system libraries

A cross compiler package ships the target's C/C++ runtime and nothing else, and a cross build looks only
in the target's own root, never at the host's libraries (they are for the wrong architecture). So a
dependency that needs another system library -- raylib's GLFW wants X11, others OpenGL or ALSA -- stops
with `Could NOT find X11` even though the host has it. The fix is a **target sysroot**: a root filesystem
for the target (`usr/include`, `usr/lib`, …) with those libraries installed.

- **Where it is looked for.** `-DCMAKE_SYSROOT=<dir>` (also in a preset), else
  `.cache/sysroots/linux-<arch>` (`linux-arm64`, `linux-arm32`, `linux-x64`) if that directory exists:
  one per architecture, shared by the gcc and clang presets, so several cross presets build one after
  another with no options. The configure prints `Target sysroot: …` or, when there is none,
  `Cross build without a target sysroot …`; `breeze/scripts/build.sh` repeats the explanation when such a
  configure fails on something not found. `.cache/sysroots/` is git-ignored.
- **What it changes.** `--sysroot` for GCC and Clang; `find_package`/`find_library` search it before the
  compiler's own root; qemu runs the result against it (`-L`) when it holds the target's dynamic loader;
  pkg-config answers from its `.pc` files only (`PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR`, and
  `PKG_CONFIG_PATH` dropped); a Debian-style `usr/lib/<triplet>` layout is found too.
- **Before the first configure, or a fresh build directory after.** A build directory keeps what CMake
  detected about the compiler the first time it was configured, so adding, changing or removing a
  sysroot afterwards stops the configure and names the directory to delete
  (`rm -rf out/build/<preset>`); `breeze/scripts/build.sh` says the same when a configure fails on a
  missing library.
- **Getting one.** Whatever gives you the target's own libraries and headers:
  - *Copy it from the target*, with its `-dev` packages installed:
    `rsync -aR pi@raspberrypi:/lib pi@raspberrypi:/usr/include pi@raspberrypi:/usr/lib .cache/sysroots/linux-arm64/`
    (absolute symlinks that come along can be made relative with `symlinks -rc`).
  - *Arch host:* the Arch Linux ARM root filesystem (archlinuxarm.org/about/downloads; check the
    signature listed there), with the packages installed through qemu. For 32-bit ARM use the `armv7`
    tarball and `linux-arm32`.
    ```bash
    sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt arch-install-scripts libarchive
    sudo systemctl restart systemd-binfmt
    mkdir -p .cache/sysroots/linux-arm64
    sudo bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C .cache/sysroots/linux-arm64
    sudo arch-chroot .cache/sysroots/linux-arm64 /bin/bash -c \
      'pacman-key --init && pacman-key --populate archlinuxarm && pacman -Syu --noconfirm libx11 libxrandr libxinerama libxcursor libxi mesa'
    ```
  - *Debian or Ubuntu host:* `debootstrap --arch=arm64 --include=libx11-dev,libxrandr-dev,libxinerama-dev,libxcursor-dev,libxi-dev,libgl-dev <suite> .cache/sysroots/linux-arm64 <mirror>`
    with `qemu-user-static` installed.
- **Or build natively.** Run the build inside that same root filesystem under qemu (`arch-chroot`,
  `chroot`) or on the device itself: an aarch64 machine takes the `linux-arm64-*` presets as native
  builds, with no sysroot involved.
- **If linking picks the wrong C library.** The sysroot's glibc is used, not the cross package's. A
  sysroot much older than the cross compiler's own glibc can fail to link; update the sysroot.

### macOS

Apple's clang is one multi-architecture compiler, so building x86_64 on Apple Silicon, or the
reverse, is an `-arch` flag, not a cross build: no sysroot, no emulator, `CMAKE_CROSSCOMPILING` stays
off. `pmn_macos_toolchain` pins `CMAKE_OSX_ARCHITECTURES` explicitly, even when it equals the
machine's (an x86_64 `cmake` under Rosetta would otherwise quietly build x86_64 for an arm64 target),
and sets `CMAKE_OSX_DEPLOYMENT_TARGET` to 11.0 unless you pass another; Apple's libc++ marks newer
library features (`std::format`, `std::pmr`, …) unavailable below the macOS that introduced them.
Universal binaries are not a target: build both presets and `lipo -create` the results. Apple's
clang (Command Line Tools) and LLVM's own, e.g. Homebrew's, both count as Clang; Homebrew's llvm is
keg-only and is where `clang-tidy` comes from, so `breeze/scripts/refactor.sh` and the hook look in
`/opt/homebrew/opt/llvm/bin` and `/usr/local/opt/llvm/bin` after `PATH`.

### Windows

- **MSVC** (`pmn_msvc_toolchain`) picks `cl`; its architecture comes from the developer environment it
  runs in, not from CMake, so the architecture check is what notices the wrong prompt (a 32-bit-
  targeting `cl` is reported with the fix). **clang-cl** picks `clang-cl` and pins
  `--target=<arch>-pc-windows-msvc`. **MSYS2 Clang** (`pmn_msys_clang_toolchain`) picks `clang++`;
  CLANG64 / CLANGARM64 decides its target. **MinGW** (`pmn_mingw_toolchain`) uses
  `<triplet>-g++` (`x86_64-w64-mingw32`, `i686-w64-mingw32`), natively on Windows or as a cross build
  from Linux, where `wine` runs the result.
- **Checks.** For the presets that link against MSVC's runtime libraries (msvc and clang-cl),
  `pmn_check_msvc_target` warns once, before CMake's compiler test fails on it, when the prompt's
  `VSCMD_ARG_TGT_ARCH` names another target or `VCToolsInstallDir\lib\<arch>\msvcrt.lib` does not
  exist, i.e. the target's Visual Studio component is not installed.
- **Runtime.** MinGW executables use a dynamic GCC runtime whose DLLs are copied beside them (see
  [Modules](#modules)).
- **`wine` hosts.** On x64 Debian/Ubuntu `wine` needs `wine64` and `wine32:i386` (an i386 multiarch
  that setup offers to enable); on Arch it lives in `multilib`, which setup offers to enable. Wine is
  not offered on ARM64 hosts.

#### Windows environments

`breeze\scripts\build.bat` calls `breeze\scripts\_winenv.bat <preset>` right before configuring. The environment
lives only in that run (`setlocal`); the user's own `cmake` is put back in front of `PATH`
afterwards, because Visual Studio's environment adds its own, often older, one.

| Presets | Environment entered |
|---|---|
| `windows-x64-msvc` `windows-arm64-msvc` | `vcvarsall.bat` of the newest Visual Studio or Build Tools that has the target's component, found with `vswhere` (the x86/x64 tools, plus the ARM64 tools for arm64, so an older Visual Studio that has them beats a newer one that doesn't), with `x64`, `x64_arm64`, `arm64` or `arm64_x64` according to the target and the machine (`x86_x64` and `x86_arm64` on 32-bit Windows). It then checks that `lib\<target>\msvcrt.lib` exists under `VCToolsInstallDir` and stops with the component to add if not: with the target's component missing, `vcvarsall` still reports the target and leaves the host's x64 `cl` on `PATH`, so neither its exit status nor `VSCMD_ARG_TGT_ARCH` is proof. |
| `windows-x64-clang-cl` `windows-arm64-clang-cl` | The same, then `clang-cl` on `PATH` if absent: `Program Files\LLVM\bin`, else Visual Studio's own copy (`VC\Tools\Llvm\x64\bin`, `…\ARM64\bin`, `…\bin`). |
| `windows-x64-mingw64` `windows-x86-mingw32` | `<MSYS2>\mingw64\bin` or `mingw32\bin` first on `PATH`, unless the preset's compiler is already on it. |
| `windows-x64-clang` `windows-arm64-clang` | `<MSYS2>\clang64\bin` or `clangarm64\bin` first on `PATH`, always: a `clang++` from elsewhere targets another ABI. `clangarm64` exists only on ARM64 Windows; on x64 the helper says so and points at the cross-building presets. |

`<MSYS2>` is `MSYS2_ROOT`, else `%SystemDrive%\msys64`. Left alone: a shell that already is a
developer prompt for the right target (`VSCMD_ARG_TGT_ARCH` and `cl` on `PATH`), presets it doesn't
know, and everything when `PMN_NO_ENV` is set. `vcvarsall` is judged by what it leaves behind, not
by its exit status; a failure prints its output and the likely fix. The helper is flat batch on
purpose (single-line `if` and `goto`, no parenthesized blocks), because the paths it expands contain
`(x86)`.

## Setup internals

`breeze/scripts/setup.sh` and `setup.bat` run four steps: check and offer the tools, fetch the pinned
Ninja, fetch the pinned Doxygen, activate the pre-commit hook (`git config core.hooksPath
breeze/githooks`). A step that cannot finish (no pinned binary for this machine, no network) says so and
the others still run.

- **Catalog.** `_tools.sh` holds one row per tool: id, required or optional, label, what it is for
  and the package for each manager. `_tools.ps1` holds the Windows equivalent. For each missing tool
  setup says what it is for, shows the exact command and waits; required tools default to yes,
  optional ones to no.
- **Cross compilers must work, not merely exist.** An AArch64, 32-bit ARM or x86-64 cross compiler
  counts as installed only if it compiles *and links* a small C++ program (which needs the target's
  assembler, headers, libstdc++, crt1.o and libc). One that can't is reported as `[part]` with the
  compiler's first error line and offered for repair. After an install the test runs again and, on a
  failure, prints `-dumpmachine`, `-print-sysroot`, `-print-prog-name=as` and the installed
  `<triplet>-*` packages.
- **Consent.** Third-party extras (today only the AUR toolchain below) are never answered by `--all`
  or by an earlier `a`: only `--everything` or a `y` typed at their own question.

### What setup can install

| Tool | apt | dnf | pacman | Homebrew |
|---|---|---|---|---|
| Git, CMake | `git` `cmake` | `git` `cmake` | `git` `cmake` | `git` `cmake` |
| C++ compiler | `g++` | `gcc-c++` | `gcc` | Xcode Command Line Tools |
| Clang | `clang` | `clang` | `clang` | Apple's, from the tools |
| clang-format | `clang-format` | `clang-tools-extra` | `clang` | `clang-format` |
| clang-tidy | `clang-tidy` | `clang-tools-extra` | `clang` | `llvm` |
| AArch64 cross | `g++-aarch64-linux-gnu` | `aarch64-linux-gnu-{binutils,gcc,glibc}` (COPR) | `aarch64-linux-gnu-gcc` (x64 hosts) | — |
| 32-bit ARM cross | `g++-arm-linux-gnueabihf` | `arm-linux-gnueabihf-{binutils,gcc,glibc}` (COPR) | AUR, below (x64 hosts) | — |
| x86-64 cross | `g++-x86-64-linux-gnu` | — | — | — |
| MinGW-w64 | `g++-mingw-w64-x86-64` `g++-mingw-w64-i686` | `mingw64-gcc-c++` `mingw32-gcc-c++` | `mingw-w64-gcc` | — |
| qemu-user | `qemu-user` | `qemu-user` | `qemu-user` | — |
| wine | `wine` `wine64` `wine32:i386` | `wine` | `wine` (multilib) | — |
| Ninja | `ninja-build` | `ninja-build` | `ninja` | `ninja` |

Ninja is only offered where no pinned download exists (32-bit ARM Linux). Fedora's own cross GCC
packages ship no libstdc++, so on dnf the ARM compilers come from lantw44's COPR, enabled only after
a separate confirmation. On Windows, setup uses winget for Git, CMake, Visual Studio 2022 Build
Tools (C++ workload), LLVM and MSYS2; adds the "MSVC ARM64 build tools" component
(`Microsoft.VisualStudio.Component.VC.Tools.ARM64`) to an existing Visual Studio through the
Visual Studio Installer's `modify` command, which asks for administrator rights; and uses MSYS2's
`pacman` for `mingw-w64-x86_64-gcc`,
`mingw-w64-i686-gcc` and `mingw-w64-clang-x86_64-clang`; it can add the tools' folders to the user
`PATH`. On macOS it runs `xcode-select --install` and, if you agree, Homebrew's installer.

**32-bit ARM on Arch** has no official package. The AUR carries ARM's own prebuilt GNU toolchain
(x86-64 hosts only) as four packages, `arm-linux-gnueabihf-{binutils,glibc-headers,glibc,gcc}-bin`.
Setup builds each from its AUR repository with `makepkg` (sources are downloaded once into
`~/.cache/pmn-aur-arm32/`) and installs all four in one transaction,
`pacman -U --noconfirm --needed --ask 4`. `--ask 4` pre-answers yes to "X and Y are in conflict.
Remove Y?" (pacman's default, and `--noconfirm`'s, is no); that is how a source-built binutils or
glibc is replaced, and it applies to any conflicting package in the transaction, which the prompt says.
Leftover `gcc-stage1` / `gcc-stage2` packages are removed first, and nothing is removed until all
four have built. Installing `arm-linux-gnueabihf-gcc-bin` alone through an AUR helper does not work:
its dependencies are generic names (`binutils`, `glibc`, `glibc-headers`), which a helper resolves
to the source-built packages (hours of compiling), leaving ARM's prebuilt GCC beside a binutils and
glibc that don't fit it.

## Script internals

- **Same options, two languages.** Each script is `.sh` (bash 3.2-compatible, macOS's default shell:
  no `mapfile`, no bash-4 expansions, empty arrays guarded for `set -u`, BSD `sed` and `mktemp`) and
  `.bat`. `_common.sh` holds what the `.sh` scripts share: reading config, resolving the build
  directory, the Homebrew llvm lookup. `build.bat` additionally enters the compiler environment
  ([Windows environments](#windows-environments)); the `.sh` scripts assume you are in the one you
  need, which on Linux and macOS is every shell.
- **Which build.** `--preset NAME` selects `out/build/NAME`, otherwise `BuildDir.cmake` picks the
  directory recorded in `out/build/.last`, falling back to `default`. `build` records the directory
  it used.
- **`build`** prefers the pinned Ninja, then one on `PATH`, then CMake's default generator with a
  warning. `cmd.exe` splits `%1`, `%2`, … on `=`, `,` and `;`, which would mangle `-DNAME=value`,
  so `build.bat` takes the preset and build type off the front and forwards the rest from the
  unsplit `%*`.
- **`run`** finds the executable in `module_manifest-<CONFIG>.txt`, reads
  `CMAKE_CROSSCOMPILING_EMULATOR` from the build's `CMakeCache.txt` and runs through it. Under
  wine it sets `XDG_RUNTIME_DIR` and a private `WINEPREFIX` in `.cache/wine/` (`WINEARCH` for the
  x86 and x64 targets); `run.bat` runs natively.
- **`install`** runs `cmake --install --component <PROJECT_CODE_NAME>` into
  `out/install/<DIST_TARGET>`.
- **`refactor`** runs clang-format, then clang-tidy with `--fix`, over `source/` and `c-api/`.

## Style and tooling

`StyleGuide.md` has two parts: C++ (PascalCase and camelCase naming) and a C API surface
(snake_case). Formatting (tabs, Allman braces, line length) comes from the single root
`.clang-format`; naming from the root `.clang-tidy`, and `c-api/.clang-tidy` swaps in the C rules for
files under `c-api/`. `.editorconfig` and `.gitattributes` keep editors and line endings in line
(`.bat` and `.ps1` stay CRLF). The pre-commit hook runs clang-format and clang-tidy on staged C/C++
files and skips with a warning when the tools are missing.

## Embedding

Used through `add_subdirectory`, the root project decides: `OUT_DIR` derives from the outermost
`CMAKE_SOURCE_DIR`, and its toolchain and presets apply.

## Verification status

- **Linux and Windows presets, Arch x64:** the 32-bit ARM presets build with the prebuilt AUR
  toolchain (reported by the maintainer). The Arch install and repair logic was also exercised
  against stand-in `pacman`, `git`, `makepkg` and cross-compiler programs: broken compiler,
  declined, `--all`, `--everything`, a failing build leaving the machine untouched.
- **`_winenv.bat`:** exercised with an emulator of the batch subset it uses against a fake machine
  (every preset, 32-bit, x64 and ARM64 hosts, already-correct prompts, an x64 machine without the
  ARM64 tools, damaged installs, and each failure path). Its first run on a real `cmd.exe` is its
  first test there.
- **Toolchain checks in `_common.cmake`** (including `pmn_check_msvc_target`): written without a
  CMake available to run them; the Arch 32-bit ARM configure was their first real run, and the
  Windows ones are untested.
- **Setup's ARM64 component row** (`Get-MsvcArm64Status`, `Install-MsvcComponent` in
  `_tools.ps1`): written without PowerShell available; only bracket and quote balance were
  checked.
- **Target sysroots** (`pmn_find_sysroot`, `pmn_use_sysroot`, the explanation `breeze/scripts/build.sh` adds to a
  failed cross configure): exercised on Linux x64 with CMake 3.28 and Ubuntu's cross compilers, against a
  *stand-in* sysroot (the cross libc, real X11 headers, and empty stub libraries compiled for the target),
  not against Arch Linux ARM or Raspberry Pi OS packages. arm64 and arm32, gcc and clang, found by
  directory and by `-DCMAKE_SYSROOT`, flat and Debian-style multiarch layouts, pkg-config kept to the
  sysroot, a sysroot without a loader, a missing one, a wrong one; a raylib 5.5 game built for arm64 stops
  with `Could NOT find X11` without a sysroot and builds with one. The native x64 and MinGW presets were
  rebuilt unchanged. The recipes above for *making* a sysroot (`rsync`, Arch Linux ARM, `debootstrap`) have
  not been run, and neither a Mac nor Windows has run any of this; the new code is reached only by Linux
  cross builds.
- **The `breeze/` and `project/` layout:** the Linux side was exercised from the finished tree and
  from the zip: the presets through the root file's `include` (and a project preset that inherits one),
  native x64 gcc, arm64 gcc and clang and arm32 gcc with and without a sysroot, MinGW from Linux, a raylib
  game for arm64, and `setup`, `build`, `run`, `install`, `docs`, `refactor`, the `cmake -P` queries and
  the pre-commit hook; also replacing `breeze/` with a pristine copy, a `project/Configuration.cmake` that
  lacks a setting, and a sysroot added or removed over an existing build directory. The changes to the
  `.bat` and `.ps1` scripts are the moved paths and the `cd` to the root, nothing else (each changed line
  was compared with the old file; CRLF endings are intact); nothing was run on Windows or on a Mac.
- **Objects modules:** built and run on Linux with gcc and clang for x64, arm64 and arm32 (the ARM ones
  under qemu), and with MinGW from Linux (built and linked; the DLL exports the pieces' symbols, nothing
  was run). A scratch tree covered pieces three deep, pieces behind a static library, a static and a
  shared library, an executable, a test and an example taking pieces, consumers discovered before their
  pieces, a raw library name in `DEPENDS`, and a cycle. Each piece appears once in the archive and on the
  link line. Not run: MSVC and macOS. For MSVC, CMake's own generator source shows the absorbed objects
  feeding the `.def` file that `WINDOWS_EXPORT_ALL_SYMBOLS` produces, so the DLL should export them; that
  is a reading, not a run.
- **A dependency declared by one module and used by another** (`fmt::fmt`, declared in `source/Core`,
  used by `source/CoreFarewell`): built with fmt 12.1.0 installed (static and shared) and not installed,
  with CMake 3.25.2, 3.27.9, 3.28.3, 3.31.6 and 4.1.2, plus a module that CMake reaches before the one
  that declares it. Cross builds ignore the host's copy and fetch one for the target.
- **macOS:** the toolchain, `TargetSelection.cmake`'s detection and the RPATH translation were
  exercised by cross-compiling to Mach-O from Linux and reading the load commands (`LC_RPATH
  @loader_path`, `@rpath/libdemo_core.dylib`, arm64 and x86_64); the scripts ran under a real bash
  3.2. No Mac has run Apple's own clang and SDK yet, so look there first if something is off.
