# =============================================================================
# project/Configuration.cmake
#
# The project's own settings: the one file to edit to say who this project is
# and where its output goes. Everything that makes the build work is the
# template's -- breeze/ -- and is replaced wholesale when the template is
# updated; nothing in this file is. Change a value here, or override a cache
# variable with -D<NAME>=... at configure time, instead of hunting through
# CMakeLists.txt, breeze/cmake/*.cmake -- or a script under breeze/scripts/ --
# for a hardcoded copy. If you find yourself typing a value this file already
# defines anywhere else, that's a bug: read it from here instead (see "How
# scripts read this file" below for the non-CMake side of that).
#
# What is NOT here: the target selection (DIST_TARGET, PLATFORM, ARCHITECTURE,
# COMPILER_ID). That is the template's, in breeze/cmake/TargetSelection.cmake.
#
# -----------------------------------------------------------------------
# Project identity
# -----------------------------------------------------------------------
#   PROJECT_CODE_NAME   machine-friendly identifier baked into every
#                        target as PROJECT_NAME_CODE (BuildHelpers.cmake's
#                        _finalize_module_target) and used as the
#                        `cmake --install --component` name (CMakeLists.txt's
#                        install() calls, breeze/scripts/install.sh / install.bat).
#   DEFAULT_BUILD_TYPE   what CMAKE_BUILD_TYPE (single-config Ninja) and
#                        the scripts' own BUILD_TYPE argument default to
#                        when nothing else is specified.
#
# -----------------------------------------------------------------------
# Output layout
# -----------------------------------------------------------------------
# Everything this project generates lives under one OUT_DIR:
#
#   out/
#     build/<preset>/                  CMAKE_BINARY_DIR -- one build tree per
#                                       preset (BUILD_OUTPUT_DIR is the
#                                       root), so switching presets never
#                                       reuses, invalidates or wipes another
#                                       preset's cache. CMakePresets.json's
#                                       binaryDir and breeze/scripts/build.sh
#                                       (-B out/build/<preset>) agree on it;
#                                       without a preset the scripts use
#                                       out/build/default. Compiled
#                                       artifacts land in
#                                       <build>/<RUNTIME_OUTPUT_SUBDIR> and
#                                       <build>/<ARCHIVE_OUTPUT_SUBDIR>
#                                       during normal day-to-day builds.
#     install/<DIST_TARGET>/{bin,lib}  what `cmake --install` / breeze/scripts/
#                                       install.sh populates -- the same
#                                       name as build/<preset>, since a
#                                       preset is named after its target.
#     dist/                            reserved for packaged/archived
#                                       output (e.g. a future CPack
#                                       integration) -- not populated by
#                                       this project yet, but the path is
#                                       configured and ready.
#     docs/<module>/html, docs/index.html   generated Doxygen output
#                                       (breeze/cmake/Documentation.cmake).
#
# One thing lives outside OUT_DIR on purpose: .cache/tools/ (TOOLCACHE_DIR)
# caches downloaded, pinned build tools (currently Ninja and Doxygen), kept
# separate so a clean `rm -rf out/` doesn't force a re-download.
#
# .gitignore is kept in sync with the paths below automatically, every
# configure -- see the bottom of this file.
#
# -----------------------------------------------------------------------
# How scripts read this file
# -----------------------------------------------------------------------
# breeze/scripts/build.sh|build.bat and breeze/scripts/install.sh|install.bat need
# values from here too (the install component name, the default build type,
# where the tool cache lives) but are running before any CMake configure exists
# to ask. They get them from breeze/cmake/PrintConfig.cmake, a tiny `cmake -P`
# script that includes this file and prints one value -- see that file for the
# exact mechanism, and any of the four scripts above for how each shell dialect
# calls it. Choosing WHICH build directory a script works on (a --preset, or the
# one built last) is the same kind of job and is done the same way, by
# breeze/cmake/BuildDir.cmake, so that logic exists once for both shell
# dialects. That's what makes this file a *real* source of truth end to end:
# nothing outside it -- not a .cmake module, not a shell script, not
# .gitignore -- hardcodes a second copy of a value defined here.
#
# One consequence: a plain `cmake -P` script never runs project() and so never
# gets real compiler detection -- WIN32, CMAKE_CXX_COMPILER_ID,
# CMAKE_SIZEOF_VOID_P etc. can't be trusted there. That is why this file holds
# settings only: everything that needs a compiler is the template's, in
# breeze/cmake/TargetSelection.cmake, which only a real configure includes (as
# it does the .gitignore sync and the other file system side effects). Keep it
# that way: anything added here must be evaluable without a compiler, must
# not touch the disk and must not message(STATUS ...) -- a script reads the
# output of its query, and a query runs far more often than a real configure.
#
# Included by CMakeLists.txt before project() (project() takes its arguments
# from the identity settings below), again by breeze/cmake/Breeze.cmake (a
# no-op, see include_guard), and directly by the `cmake -P` scripts named
# above -- a bare invocation like that never goes through CMakeLists.txt's own
# cmake_minimum_required(), so without one of its own here, this file's
# `IN_LIST` checks (and BuildDir.cmake's) would run under whatever policy
# CMake defaults to outside a project -- OLD on any CMake still old enough to
# make that a real choice (CMP0057 -- IN_LIST inside if() -- was NEW-only-by-
# default for a long stretch of CMake versions before finally being removed
# outright in CMake 4.0), which turns `if(x IN_LIST y)` into a straight parse
# error. Repeating the same version CMakeLists.txt already requires is a
# harmless no-op there; it's what makes every OTHER way into this file safe
# too.
# =============================================================================

cmake_minimum_required(VERSION 3.25)
include_guard(GLOBAL)

# -------------------------------------------------------
# Project identity
# -------------------------------------------------------
# What CMakeLists.txt hands to project(): the name, version, description and
# languages, and the C++ standard breeze/cmake/Breeze.cmake then applies.
set(PROJECT_TITLE          "DemoApp")
set(PROJECT_VERSION_NUMBER "0.1.0")
set(PROJECT_SUMMARY        "Demo app exercising the generator-friendly CMake module system")
set(PROJECT_LANGUAGES      CXX)
set(PROJECT_CXX_STANDARD   20)

# -------------------------------------------------------
set(PROJECT_CODE_NAME "demo" CACHE STRING
    "Machine-friendly identifier: baked into targets as PROJECT_NAME_CODE and used as the `cmake --install` component name")

set(DEFAULT_BUILD_TYPE "Release" CACHE STRING
    "CMAKE_BUILD_TYPE / scripts BUILD_TYPE default when none is given")

# -------------------------------------------------------
# Output paths
# -------------------------------------------------------
set(OUT_DIR "${CMAKE_SOURCE_DIR}/out" CACHE PATH
    "Root directory for everything this project generates: build artifacts, install trees, docs, and reserved dist packaging output")

set(DIST_OUTPUT_DIR "${OUT_DIR}/dist" CACHE PATH
    "Reserved for packaged/archived distribution output (e.g. a future CPack integration). Not populated by this project yet.")

set(BUILD_OUTPUT_DIR "${OUT_DIR}/build" CACHE PATH
    "Root of the build trees: one subdirectory (the CMAKE_BINARY_DIR) per preset, so switching presets never reuses or wipes another preset's build")

set(INSTALL_OUTPUT_DIR "${OUT_DIR}/install" CACHE PATH
    "Root of the cmake --install destination tree, one subdirectory per DIST_TARGET")

set(DOCS_OUTPUT_DIR "${OUT_DIR}/docs" CACHE PATH
    "Root of generated Doxygen documentation, one subdirectory per module")

set(COMPILE_COMMANDS_DESTINATION "${CMAKE_SOURCE_DIR}/compile_commands.json" CACHE FILEPATH
    "Where compile_commands.json is copied to after every build, for clangd/clang-tidy tooling (see CMakeLists.txt)")

# Deliberately NOT under OUT_DIR: this caches downloaded, pinned build
# tools (Ninja and Doxygen -- see breeze/cmake/FetchNinja.cmake and
# breeze/cmake/FetchDoxygen.cmake), which are machine-local and expensive to
# re-fetch, not build output. Keeping it separate means a clean `rm -rf
# out/` (a normal "start fresh" gesture) doesn't force a re-download.
set(TOOLCACHE_DIR "${CMAKE_SOURCE_DIR}/.cache/tools" CACHE PATH
    "Where pinned build tools (currently Ninja and Doxygen) are cached, kept separate from OUT_DIR")


# Subdirectory NAMES only (not full paths) for where compiled artifacts
# land inside whatever the current build directory is (CMAKE_BINARY_DIR) --
# these apply correctly no matter where -B points, including if you build
# outside out/build/<preset> entirely. LIBRARY defaults to the same subdirectory as
# RUNTIME because shared libraries need to sit next to the executables
# that load them via the project's $ORIGIN-relative RPATH strategy (see
# CMakeLists.txt).
set(RUNTIME_OUTPUT_SUBDIR "bin" CACHE STRING "Build-dir subdirectory for runtime artifacts (executables, .dll, .so)")
set(LIBRARY_OUTPUT_SUBDIR "bin" CACHE STRING "Build-dir subdirectory for shared-library artifacts")
set(ARCHIVE_OUTPUT_SUBDIR "lib" CACHE STRING "Build-dir subdirectory for static/import-library artifacts (.a, .lib)")
