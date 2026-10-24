# =============================================================================
# PrintConfig.cmake
#
# Script-mode bridge: lets breeze/scripts/*.sh and breeze/scripts/*.bat read values out of
# project/Configuration.cmake -- this project's single source of truth (see that
# file) -- instead of hardcoding a second copy that can silently drift out
# of sync. This is exactly the bug it replaces: breeze/scripts/install.sh and
# install.bat used to each hardcode their own literal "demo", with a
# comment warning it had to be kept in sync with PROJECT_CODE_NAME by hand.
#
# Usage:
#   cmake "-DPRINT_VARS=NAME1;NAME2;..." -P breeze/cmake/PrintConfig.cmake
#
# Prints one "NAME=value" line per requested variable, in the order given.
# Every line is emitted via message(STATUS ...) -- deliberately: it's the
# only message() mode CMake sends to stdout (verified directly: the
# no-keyword default, NOTICE, and WARNING all go to stderr; STATUS is the
# one exception), which is what lets a caller capture it with plain output
# redirection/command substitution instead of needing a temp file. The
# tradeoff is that STATUS always prefixes the line with "-- ", so every
# caller strips that off along with the "NAME=" it already knows: see
# breeze/scripts/build.sh's _pmn_read_config() or breeze/scripts/build.bat's
# :read_config for the one small wrapper each shell dialect uses -- every
# script that needs a value calls that wrapper rather than re-deriving
# this convention itself.
#
# Includes project/Configuration.cmake, which holds settings only: nothing in
# it needs a compiler and it touches nothing on disk, which is what makes it
# safe here -- a value lookup shouldn't have side effects, and this runs far
# more often than a real configure. What does need a real compiler
# (DIST_TARGET/PLATFORM/ARCHITECTURE/COMPILER_ID, which a plain `cmake -P`
# script would get wrong: project(... LANGUAGES CXX) never runs) is
# breeze/cmake/TargetSelection.cmake, not included here. So only ask for names
# the settings file defines -- PROJECT_CODE_NAME, DEFAULT_BUILD_TYPE, the path
# variables; see that file's header for the rules on adding to it.
# =============================================================================

if(NOT DEFINED PRINT_VARS)
    message(FATAL_ERROR "Usage: cmake \"-DPRINT_VARS=NAME1;NAME2;...\" -P breeze/cmake/PrintConfig.cmake")
endif()

get_filename_component(CMAKE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${CMAKE_SOURCE_DIR}/project/Configuration.cmake")

foreach(_pmn_print_name ${PRINT_VARS})
    if(NOT DEFINED ${_pmn_print_name})
        message(FATAL_ERROR
            "PrintConfig.cmake: '${_pmn_print_name}' is not defined by "
            "project/Configuration.cmake -- see that file's header "
            "('How scripts read this file').")
    endif()
    message(STATUS "${_pmn_print_name}=${${_pmn_print_name}}")
endforeach()
