# =============================================================================
# .gitignore sync
#
# Keeps a marked block in .gitignore in sync with the actual, current
# values of the path variables above -- every configure, automatically.
# Nothing outside that block (e.g. the Visual Studio template this
# project's .gitignore starts from) is ever touched. This is what makes
# this file the real source of truth for these paths specifically: change
# OUT_DIR (or override it with -DOUT_DIR=...) and .gitignore updates on
# the next configure instead of silently drifting out of sync with what
# actually gets generated.
#
# If .gitignore doesn't exist yet, it's created with just this block. If
# it exists but has no markers yet, the block is appended. If the markers
# are already there, only the content between them is replaced. The file
# is only rewritten when the computed content actually differs, so a
# normal reconfigure doesn't spuriously touch it (or its mtime).
#
# A path is only added if it resolves inside the repo (CMAKE_SOURCE_DIR)
# -- e.g. an overridden TOOLCACHE_DIR pointing somewhere else entirely is
# silently skipped, since .gitignore has nothing meaningful to say about
# a location outside the repository it lives in.
#
# Skipped entirely in query mode -- see "How scripts read this file"
# above.
# =============================================================================

include_guard(GLOBAL)

# out/dist/ is reserved (see the output layout in project/Configuration.cmake) and
# nothing writes to it yet, so it is created eagerly here -- otherwise it simply
# would not exist until something populates it, which could easily read as "this
# was never wired up" rather than "intentionally reserved for later". A file
# system side effect, so it lives here and not in the settings file: a script's
# query of those settings runs far more often than a real configure.
file(MAKE_DIRECTORY "${DIST_OUTPUT_DIR}")

set(_pmn_gitignore_begin "# >>> Configuration.cmake generated paths -- BEGIN (do not edit by hand; edit Configuration.cmake and reconfigure) >>>")
set(_pmn_gitignore_end   "# <<< Configuration.cmake generated paths -- END <<<")

function(_pmn_gitignore_relpath ABSOLUTE_VALUE OUT_VAR)
    file(RELATIVE_PATH _pmn_rel "${CMAKE_SOURCE_DIR}" "${ABSOLUTE_VALUE}")
    if(_pmn_rel MATCHES "^\\.\\.")
        set(${OUT_VAR} "" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "${_pmn_rel}" PARENT_SCOPE)
    endif()
endfunction()

set(_pmn_gitignore_entries "")
foreach(_pmn_dir_var OUT_DIR BUILD_OUTPUT_DIR DIST_OUTPUT_DIR INSTALL_OUTPUT_DIR DOCS_OUTPUT_DIR TOOLCACHE_DIR)
    _pmn_gitignore_relpath("${${_pmn_dir_var}}" _pmn_rel)
    if(_pmn_rel)
        list(APPEND _pmn_gitignore_entries "${_pmn_rel}/")
    endif()
endforeach()

_pmn_gitignore_relpath("${COMPILE_COMMANDS_DESTINATION}" _pmn_cc_rel)
if(_pmn_cc_rel)
    list(APPEND _pmn_gitignore_entries "${_pmn_cc_rel}")
endif()

# breeze/scripts/run.sh keeps the wine prefixes it creates in .cache/wine/ -- a
# fixed place, not one of the path variables above. Listed here rather
# than added to .gitignore by hand: this block is rewritten on every
# configure, which silently deleted a hand-added line.
list(APPEND _pmn_gitignore_entries ".cache/wine/")
# Likewise the target sysroots breeze/cmake/toolchains/_common.cmake looks for
# in .cache/sysroots/linux-<arch> (see pmn_find_sysroot there): root
# filesystems for cross builds, hundreds of megabytes, never to commit.
list(APPEND _pmn_gitignore_entries ".cache/sysroots/")

list(REMOVE_DUPLICATES _pmn_gitignore_entries)
list(SORT _pmn_gitignore_entries)

set(_pmn_gitignore_block_content "")
foreach(_pmn_entry ${_pmn_gitignore_entries})
    string(APPEND _pmn_gitignore_block_content "${_pmn_entry}\n")
endforeach()

set(_pmn_gitignore_path "${CMAKE_SOURCE_DIR}/.gitignore")
set(_pmn_gitignore_new_block "${_pmn_gitignore_begin}\n${_pmn_gitignore_block_content}${_pmn_gitignore_end}")

if(EXISTS "${_pmn_gitignore_path}")
    file(READ "${_pmn_gitignore_path}" _pmn_gitignore_content)
else()
    set(_pmn_gitignore_content "")
endif()

string(FIND "${_pmn_gitignore_content}" "${_pmn_gitignore_begin}" _pmn_gitignore_begin_pos)
string(FIND "${_pmn_gitignore_content}" "${_pmn_gitignore_end}" _pmn_gitignore_end_pos)

if(_pmn_gitignore_begin_pos GREATER -1 AND _pmn_gitignore_end_pos GREATER -1
   AND _pmn_gitignore_end_pos GREATER _pmn_gitignore_begin_pos)
    # Replace only the content between the existing markers.
    string(SUBSTRING "${_pmn_gitignore_content}" 0 ${_pmn_gitignore_begin_pos} _pmn_gitignore_before)
    string(LENGTH "${_pmn_gitignore_end}" _pmn_gitignore_end_marker_len)
    math(EXPR _pmn_gitignore_after_start "${_pmn_gitignore_end_pos} + ${_pmn_gitignore_end_marker_len}")
    string(SUBSTRING "${_pmn_gitignore_content}" ${_pmn_gitignore_after_start} -1 _pmn_gitignore_after)
    set(_pmn_gitignore_final "${_pmn_gitignore_before}${_pmn_gitignore_new_block}${_pmn_gitignore_after}")
else()
    # No markers yet -- append (trimming trailing blank lines first so we
    # don't accumulate extra blank lines across repeated appends).
    string(REGEX REPLACE "\n+$" "" _pmn_gitignore_trimmed "${_pmn_gitignore_content}")
    if(_pmn_gitignore_trimmed STREQUAL "")
        set(_pmn_gitignore_final "${_pmn_gitignore_new_block}\n")
    else()
        set(_pmn_gitignore_final "${_pmn_gitignore_trimmed}\n\n${_pmn_gitignore_new_block}\n")
    endif()
endif()

if(NOT _pmn_gitignore_final STREQUAL _pmn_gitignore_content)
    file(WRITE "${_pmn_gitignore_path}" "${_pmn_gitignore_final}")
endif()
