# =============================================================================
# BuildDir.cmake
#
# Script-mode bridge, the same idea as PrintConfig.cmake: tells
# breeze/scripts/*.sh and breeze/scripts/*.bat which build directory to work on, so that
# logic exists once here instead of twice in two shell dialects.
#
# Every preset builds in its own directory, out/build/<name> (see
# BUILD_OUTPUT_DIR in project/Configuration.cmake), which is what lets you switch
# presets without one's cache clobbering another's. The scripts have to
# pick one of them:
#
#   build.*             knows the name already (--preset <name>, else
#                        "default") and only needs the path. After a
#                        successful configure it also records the choice as
#                        the one built last.
#   run.* install.*     take an optional --preset <name>; without it they use
#   docs.*               the directory that was built last, or the only one
#                        that exists, or say what to do if that's ambiguous.
#
# Usage:
#   cmake [-DPMN_NAME=<name>] [-DPMN_RECORD=ON] -P breeze/cmake/BuildDir.cmake
#
#   PMN_NAME     a preset name, or "default". Given: the answer is
#                BUILD_OUTPUT_DIR/<name>, whether or not it exists yet (build
#                is about to create it). Not given: discover one -- the one
#                built last, else the only one, else an error.
#   PMN_RECORD   also remember PMN_NAME as the one built last (a one-line
#                file, out/build/.last).
#
# Prints exactly one line, via message(STATUS ...) for the reason
# PrintConfig.cmake documents (STATUS is the one message() mode CMake sends
# to stdout, at the cost of a "-- " prefix every caller strips):
#
#   -- BUILD_DIR=<path>   relative to the project root with forward slashes
#                         when it's inside the project (the normal case),
#                         absolute otherwise
#   -- ERROR=<text>       what to tell the user
#
# The exit status is 0 either way -- callers key on which line they got. The
# error text sticks to plain words and avoids the characters cmd.exe treats
# specially (& | < > ^ % ! and parentheses), so a .bat can echo it back
# verbatim.
# =============================================================================

get_filename_component(CMAKE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${CMAKE_SOURCE_DIR}/project/Configuration.cmake")

# <path> shown relative to the project root when it's inside it.
function(_pmn_display_path ABSOLUTE_PATH OUT_VAR)
    file(RELATIVE_PATH _pmn_rel "${CMAKE_SOURCE_DIR}" "${ABSOLUTE_PATH}")
    if(_pmn_rel MATCHES "^\\.\\.")
        set(${OUT_VAR} "${ABSOLUTE_PATH}" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "${_pmn_rel}" PARENT_SCOPE)
    endif()
endfunction()

set(_pmn_root "${BUILD_OUTPUT_DIR}")
_pmn_display_path("${_pmn_root}" _pmn_root_shown)

set(_pmn_key "")
set(_pmn_value "")

if(NOT "${PMN_NAME}" STREQUAL "")
    # ---- A name was given: the answer is just the path. ----------------------
    if(PMN_NAME MATCHES "[/\\\\]" OR PMN_NAME STREQUAL "." OR PMN_NAME STREQUAL "..")
        set(_pmn_key "ERROR")
        set(_pmn_value "'${PMN_NAME}' is not a valid preset name: it must be a single directory name, not a path.")
    else()
        _pmn_display_path("${_pmn_root}/${PMN_NAME}" _pmn_shown)
        set(_pmn_key "BUILD_DIR")
        set(_pmn_value "${_pmn_shown}")
        if(PMN_RECORD)
            file(MAKE_DIRECTORY "${_pmn_root}")
            file(WRITE "${_pmn_root}/.last" "${PMN_NAME}\n")
        endif()
    endif()
else()
    # ---- No name: discover one. ---------------------------------------------
    # Candidates are the subdirectories that hold a CMake cache.
    set(_pmn_candidates "")
    file(GLOB _pmn_children LIST_DIRECTORIES true "${_pmn_root}/*")
    foreach(_pmn_child IN LISTS _pmn_children)
        if(IS_DIRECTORY "${_pmn_child}" AND EXISTS "${_pmn_child}/CMakeCache.txt")
            get_filename_component(_pmn_child_name "${_pmn_child}" NAME)
            list(APPEND _pmn_candidates "${_pmn_child_name}")
        endif()
    endforeach()
    list(SORT _pmn_candidates)
    list(LENGTH _pmn_candidates _pmn_count)

    # The one built last, if that pointer still names a real build.
    set(_pmn_last "")
    if(EXISTS "${_pmn_root}/.last")
        file(STRINGS "${_pmn_root}/.last" _pmn_last_lines LIMIT_COUNT 1)
        string(STRIP "${_pmn_last_lines}" _pmn_last)
    endif()

    set(_pmn_chosen "")
    if(NOT "${_pmn_last}" STREQUAL "" AND "${_pmn_last}" IN_LIST _pmn_candidates)
        set(_pmn_chosen "${_pmn_last}")
    elseif(_pmn_count EQUAL 1)
        set(_pmn_chosen "${_pmn_candidates}")
    endif()

    if(NOT "${_pmn_chosen}" STREQUAL "")
        _pmn_display_path("${_pmn_root}/${_pmn_chosen}" _pmn_shown)
        set(_pmn_key "BUILD_DIR")
        set(_pmn_value "${_pmn_shown}")
    elseif(_pmn_count EQUAL 0)
        set(_pmn_key "ERROR")
        if(EXISTS "${_pmn_root}/CMakeCache.txt")
            set(_pmn_value "${_pmn_root_shown} holds a build from the old single-directory layout, which this version no longer uses. Delete it, then run breeze/scripts/build to create one build directory per preset.")
        else()
            set(_pmn_value "No build found under ${_pmn_root_shown}. Run breeze/scripts/build first, optionally with --preset NAME.")
        endif()
    else()
        list(JOIN _pmn_candidates ", " _pmn_names)
        set(_pmn_key "ERROR")
        set(_pmn_value "Several builds exist under ${_pmn_root_shown} and none was built last through the scripts: ${_pmn_names}. Pass --preset NAME to choose one.")
    endif()
endif()

message(STATUS "${_pmn_key}=${_pmn_value}")
