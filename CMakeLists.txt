# =============================================================================
# CMakeLists.txt -- the project's entry point
#
# Deliberately tiny, and the project's: nothing in it changes when the template
# does. Two directories hold everything else:
#
#   project/   this project's settings -- its name, version, languages, C++
#              standard, output layout (project/Configuration.cmake)
#   breeze/    the template: the build system, toolchains, scripts and docs.
#              Replace it wholesale to update the template.
#
# source/ (modules), vendor/ (vendored code) and out/ (everything generated)
# stay at the root, as does c-api/ if you use it.
# =============================================================================

cmake_minimum_required(VERSION 3.25)

# project() takes its arguments from the settings, so they are read first. The
# file holds settings only (no compiler needed), which is what lets the scripts
# read the same file without a configure.
include("${CMAKE_CURRENT_SOURCE_DIR}/project/Configuration.cmake")

project(
    ${PROJECT_TITLE}
    VERSION ${PROJECT_VERSION_NUMBER}
    DESCRIPTION "${PROJECT_SUMMARY}"
    LANGUAGES ${PROJECT_LANGUAGES}
)

# Everything else -- target selection, output paths, module discovery, install
# rules -- is the template's. Add project-wide CMake of your own below this line
# (or above it, if it has to come before the template's), not in breeze/.
include("${CMAKE_CURRENT_SOURCE_DIR}/breeze/cmake/Breeze.cmake")
