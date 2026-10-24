# =============================================================================
# Dependencies.cmake
#
# Three ways to bring in a third-party dependency, and one helper that ties
# two of them together. All three keep the dependency's own warnings out of
# your build (SYSTEM) and its sources out of compile_commands.json, so
# clangd/clang-tidy stay focused on code this project owns.
#
#   add_vendor_header_only(NAME [INCLUDE_DIR <dir>])
#       A buildless (header-only) drop checked into vendor/<NAME>/include
#       (or vendor/<INCLUDE_DIR>). Wraps it as an INTERFACE target NAME.
#
#   add_vendor_subdirectory(SUBDIR)
#       A vendored dependency that ships its own CMakeLists.txt, checked
#       into vendor/<SUBDIR> (a plain source drop, git submodule, or git
#       subtree). Whatever target names that CMakeLists.txt defines are
#       what you DEPENDS on.
#
#   add_dependency(NAME <FetchContent_Declare args...>)
#       CMake's native find_package + FetchContent integration: pass
#       FIND_PACKAGE_ARGS ... to try an already-installed copy (an apt/
#       vcpkg/conan package) first, and only download + build from source
#       if nothing is found. Omit FIND_PACKAGE_ARGS to always fetch.
#       https://cmake.org/cmake/help/latest/module/FetchContent.html#integrating-with-find-package
#
# All three are safe to call more than once for the same name (e.g. two
# modules that both need the same dependency) -- later calls are no-ops.
#
# A module DEPENDS on whatever target the chosen path defines, exactly
# like depending on another module -- add_lib_module/add_exe_module/etc. don't
# need to know or care which of the three supplied it.
#
# IMPORTANT -- installing: a vendored/fetched dependency's own
# CMakeLists.txt usually has its own install() rules, and there is no
# reliable, version-independent way to suppress them from here (EXCLUDE_
# FROM_ALL's effect on install() is explicitly documented as undefined,
# and CMAKE_SKIP_INSTALL_RULES breaks `cmake --install` outright for
# FetchContent -- both were tried and rejected). The actual fix lives in
# CMakeLists.txt: our own install(TARGETS ...) calls are tagged
# COMPONENT ${PROJECT_CODE_NAME}, and breeze/scripts/install.sh / install.bat always pass
# --component so a third-party dependency's untagged install rules are
# never pulled in. Installing with plain `cmake --install build` (no
# --component) will also install whatever the dependency wanted to
# install, typically under CMAKE_INSTALL_PREFIX (e.g. /usr/local) --
# use the install script, or pass --component yourself.
# =============================================================================

include_guard(GLOBAL)

# -----------------------------------------------------------------------
# _exclude_from_compile_commands(DIR): drop every target defined under
# DIR from compile_commands.json. Applied to vendored/fetched third-party
# code so the exported compile database stays focused on code this
# project actually owns.
# -----------------------------------------------------------------------
function(_exclude_from_compile_commands DIR)
    if(NOT IS_DIRECTORY "${DIR}")
        return()
    endif()
    get_property(_pmn_dir_targets DIRECTORY "${DIR}" PROPERTY BUILDSYSTEM_TARGETS)
    foreach(_t ${_pmn_dir_targets})
        set_target_properties(${_t} PROPERTIES EXPORT_COMPILE_COMMANDS OFF)
    endforeach()
endfunction()

# -----------------------------------------------------------------------
# add_vendor_header_only(NAME [INCLUDE_DIR <dir>])
# -----------------------------------------------------------------------
macro(add_vendor_header_only NAME)
    cmake_parse_arguments(ARG "" "INCLUDE_DIR" "" ${ARGN})
    if(NOT TARGET ${NAME})
        add_library(${NAME} INTERFACE)
        if(ARG_INCLUDE_DIR)
            target_include_directories(${NAME} SYSTEM INTERFACE "${CMAKE_SOURCE_DIR}/vendor/${ARG_INCLUDE_DIR}")
        else()
            target_include_directories(${NAME} SYSTEM INTERFACE "${CMAKE_SOURCE_DIR}/vendor/${NAME}/include")
        endif()
    endif()
endmacro()

# -----------------------------------------------------------------------
# add_vendor_subdirectory(SUBDIR)
#
# EXCLUDE_FROM_ALL means only targets actually depended on via
# target_link_libraries get built. SYSTEM marks its headers so our
# per-module warning flags (added only by add_lib_module/add_objects_module/
# add_exe_module/etc., never globally) don't fire when *our* code includes them.
# -----------------------------------------------------------------------
macro(add_vendor_subdirectory SUBDIR)
    get_property(_pmn_vendor_added GLOBAL PROPERTY PMN_VENDOR_ADDED_${SUBDIR} SET)
    if(NOT _pmn_vendor_added)
        set_property(GLOBAL PROPERTY PMN_VENDOR_ADDED_${SUBDIR} TRUE)
        add_subdirectory(
            "${CMAKE_SOURCE_DIR}/vendor/${SUBDIR}"
            "${CMAKE_BINARY_DIR}/vendor/${SUBDIR}"
            EXCLUDE_FROM_ALL SYSTEM
        )
        _exclude_from_compile_commands("${CMAKE_SOURCE_DIR}/vendor/${SUBDIR}")
    endif()
endmacro()

# -----------------------------------------------------------------------
# add_dependency(NAME <FetchContent_Declare args...>)
#
# Example -- prefer an installed copy that's new enough, fetch+build from
# source otherwise:
#   add_dependency(fmt
#       GIT_REPOSITORY https://github.com/fmtlib/fmt.git
#       GIT_TAG        12.1.0
#       GIT_SHALLOW    TRUE
#       FIND_PACKAGE_ARGS 12 NAMES fmt
#   )
#   add_lib_module(mylib DEPENDS fmt::fmt)
#
# Always give FIND_PACKAGE_ARGS a minimum version (the "12" above). Without
# one, ANY installed copy beats the pinned GIT_TAG -- including a distro
# package years older than the pin -- so a "pinned" dependency isn't. A
# dependency's own CMake options (fmt's FMT_MODULE, say) are set with
# set(<OPTION> <value> CACHE ...) BEFORE this call. source/Core/CMakeLists.txt
# is the real, commented instance of both.
#
# FetchContent_MakeAvailable() is documented idempotent per name, so
# calling this more than once for the same NAME (from multiple modules)
# is safe.
#
# The targets it makes are usable from EVERY module, wherever the call is
# made and whichever module CMake reaches first -- one module can declare
# fmt and another just DEPENDS on fmt::fmt. A copy built from source gets
# that for free (its targets are global). An installed copy found through
# FIND_PACKAGE_ARGS does not: find_package() defines imported targets in the
# directory that called it and below, so a sibling module's
# target_link_libraries(... fmt::fmt) failed with "target was not found" --
# only on machines that happen to have the package installed. Hence
# CMAKE_FIND_PACKAGE_TARGETS_GLOBAL, for the duration of FetchContent_
# MakeAvailable -- not of FetchContent_Declare, which reads the variable too
# and, in CMake 3.24 to 3.28 at least, builds a broken find_package() call
# from it ("Argument not separated from preceding token by whitespace").
# -----------------------------------------------------------------------
macro(add_dependency NAME)
    include(FetchContent)
    FetchContent_Declare(${NAME} SYSTEM ${ARGN})
    if(DEFINED CMAKE_FIND_PACKAGE_TARGETS_GLOBAL)
        set(_pmn_prev_targets_global "${CMAKE_FIND_PACKAGE_TARGETS_GLOBAL}")
    else()
        unset(_pmn_prev_targets_global)
    endif()
    set(CMAKE_FIND_PACKAGE_TARGETS_GLOBAL ON)
    FetchContent_MakeAvailable(${NAME})
    if(DEFINED _pmn_prev_targets_global)
        set(CMAKE_FIND_PACKAGE_TARGETS_GLOBAL "${_pmn_prev_targets_global}")
    else()
        unset(CMAKE_FIND_PACKAGE_TARGETS_GLOBAL)
    endif()
    unset(_pmn_prev_targets_global)
    string(TOLOWER "${NAME}" _pmn_lc_name)
    if(DEFINED ${_pmn_lc_name}_SOURCE_DIR)
        _exclude_from_compile_commands("${${_pmn_lc_name}_SOURCE_DIR}")
    endif()
endmacro()
