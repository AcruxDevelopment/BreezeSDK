# =============================================================================
# Documentation.cmake
#
# Automatic, per-module Doxygen documentation, using a pinned Doxygen
# version -- never your system's doxygen, so every machine gets identical
# output. Zero setup required at the CMakeLists.txt level: every module
# registered via add_lib_module/add_objects_module/add_exe_module/
# add_test_module/add_example_module gets its own documentation target for free -- nothing
# to add to a module's own CMakeLists.txt. Vendored and fetched
# dependencies (breeze/cmake/Dependencies.cmake) are never auto-documented, same
# reasoning as their compile_commands.json exclusion: it's not your code.
#
# IMPORTANT: this file only ever LOOKS for an already-downloaded pinned
# Doxygen (see breeze/cmake/DoxygenPin.cmake for where) -- it never downloads
# anything itself, so a plain `breeze/scripts/build.sh` never touches Doxygen or
# needs network access. Run `breeze/scripts/setup.sh` / `setup.bat` once (which
# runs breeze/cmake/FetchDoxygen.cmake) to actually fetch it; until then,
# documentation targets print a message pointing at that script instead
# of building, and everything else builds completely normally.
#
# What gets generated, per module <target>, once set up:
#   out/docs/<target>/html/index.html   -- via `cmake --build <build-dir> --target docs_<target>`
# Plus one landing page linking to all of them:
#   out/docs/index.html                 -- via `cmake --build <build-dir> --target docs`
# (or just run breeze/scripts/docs.sh / docs.bat, which builds `docs` and prints the path)
# Paths above use the defaults from project/Configuration.cmake (DOCS_OUTPUT_DIR).
#
# Configuring it:
#   -DENABLE_DOXYGEN=OFF                disable entirely (skips even the presence check)
#   -DDOXYGEN_PINNED_VERSION=1.17.0     use a different pinned version (also
#       update the two SHA256 hashes in breeze/cmake/DoxygenPin.cmake to match
#       that release's assets, and re-run breeze/scripts/setup.sh)
#   -DDOXYGEN_WARN_IF_UNDOCUMENTED=YES / -DDOXYGEN_QUIET=NO   stricter/louder output
#   -DDOXYGEN_<ANY_DOXYFILE_TAG>=...    any Doxyfile tag can be set this way --
#       see https://www.doxygen.nl/manual/config.html
# A module can opt out with NO_DOCS, e.g.:
#   add_lib_module(core_lib TYPE SHARED NO_DOCS ...)
# =============================================================================

include_guard(GLOBAL)

option(ENABLE_DOXYGEN "Generate per-module Doxygen documentation using a pinned, project-managed Doxygen (run breeze/scripts/setup.sh once to fetch it)" ON)

if(ENABLE_DOXYGEN)
    include("${CMAKE_CURRENT_LIST_DIR}/DoxygenPin.cmake")

    if(NOT DOXYGEN_PIN_PLATFORM_SUPPORTED)
        message(WARNING "No pinned Doxygen ${DOXYGEN_PINNED_VERSION} binary is configured for this "
                         "host platform. Install Doxygen ${DOXYGEN_PINNED_VERSION} manually, make sure "
                         "it's on PATH or pass -DDOXYGEN_EXECUTABLE=/path/to/doxygen, or extend "
                         "breeze/cmake/DoxygenPin.cmake with a download URL + hash for this platform.")
        set(ENABLE_DOXYGEN OFF)
    elseif(NOT EXISTS "${DOXYGEN_PIN_EXECUTABLE}")
        # Not fetched yet -- see the file header. Deliberately not a
        # message() here: this is the normal, expected state before
        # breeze/scripts/setup.sh has ever run, not something to warn about.
        set(ENABLE_DOXYGEN OFF)
    else()
        # Pre-seed DOXYGEN_EXECUTABLE with our pinned path *before*
        # find_package(Doxygen) runs, rather than overriding it
        # afterward. find_program() (which find_package uses internally)
        # does not re-search when the cache variable already holds a
        # valid path -- so this makes find_package() treat our pinned
        # copy as the one it found, and run its own normal success path
        # using it: creating the Doxygen::doxygen imported target,
        # determining DOXYGEN_VERSION, and generating the Doxyfile
        # template doxygen_add_docs() needs. All of that only happens as
        # a side effect of find_package() succeeding -- overriding
        # DOXYGEN_EXECUTABLE *after* calling it (the previous approach
        # here) leaves those steps never having run at all, which
        # doxygen_add_docs() then fails on. This way we don't have to
        # reimplement any of find_package's own (undocumented, and
        # confirmed version-dependent -- CMake 3.28 and 4.3 both hit
        # this differently) internal machinery ourselves.
        set(DOXYGEN_EXECUTABLE "${DOXYGEN_PIN_EXECUTABLE}" CACHE FILEPATH "Pinned Doxygen executable (never the system's)" FORCE)
    endif()
endif()

if(ENABLE_DOXYGEN)
    # Also searches for `dot` (Graphviz) for call graphs -- an optional,
    # system-detected enhancement, unrelated to the doxygen executable
    # itself, which is pre-seeded above to always resolve to our pinned
    # copy rather than a system one.
    find_package(Doxygen QUIET OPTIONAL_COMPONENTS dot)

    if(NOT DOXYGEN_FOUND)
        message(WARNING "Pre-seeding DOXYGEN_EXECUTABLE with the pinned Doxygen at "
                         "${DOXYGEN_PIN_EXECUTABLE} did not result in find_package(Doxygen) "
                         "succeeding. Documentation will be disabled for this configure.")
        set(ENABLE_DOXYGEN OFF)
    endif()
endif()

if(ENABLE_DOXYGEN)
    message(STATUS "Doxygen ${DOXYGEN_VERSION} ready (pinned, not system-installed: ${DOXYGEN_EXECUTABLE}) -- per-module documentation enabled")

    # Project-wide defaults, one Doxyfile tag per DOXYGEN_<TAG> variable.
    # Override any of them with -DDOXYGEN_<TAG>=... at configure time.
    # Kept deliberately quiet and lenient by default (no warnings about
    # undocumented entities) so a freshly generated module with zero
    # doxygen comments still produces clean, useful output -- browsable
    # files/functions/call graphs -- instead of a wall of warnings.
    set(DOXYGEN_GENERATE_HTML YES)
    set(DOXYGEN_GENERATE_LATEX NO)
    set(DOXYGEN_EXTRACT_ALL YES)
    set(DOXYGEN_EXTRACT_STATIC YES)
    set(DOXYGEN_EXTRACT_PRIVATE NO)
    set(DOXYGEN_WARN_IF_UNDOCUMENTED NO)
    set(DOXYGEN_QUIET YES)
    set(DOXYGEN_RECURSIVE YES)
    set(DOXYGEN_SOURCE_BROWSER YES)
    set(DOXYGEN_GENERATE_TREEVIEW YES)
    if(DOXYGEN_DOT_FOUND)
        set(DOXYGEN_HAVE_DOT YES)
        set(DOXYGEN_CALL_GRAPH YES)
        set(DOXYGEN_CALLER_GRAPH YES)
    endif()

    add_custom_target(docs COMMENT "Build documentation for every module")
else()
    add_custom_target(docs
        COMMAND ${CMAKE_COMMAND} -E echo
            "Documentation isn't set up yet (or ENABLE_DOXYGEN=OFF). Run breeze/scripts/setup.sh (or setup.bat) once to fetch the pinned Doxygen, then reconfigure."
        VERBATIM
    )
endif()

# -----------------------------------------------------------------------
# _add_module_docs(TARGET): called automatically from _finalize_module_target
# for every module -- creates docs_<TARGET> (a Doxygen run scoped to that
# module's own directory) and wires it into the aggregate `docs` target.
# A no-op if ENABLE_DOXYGEN is off. Excluded from the default build same
# as tests/examples -- documentation is opt-in per build, not generated
# on every compile.
#
# If the module's own directory has a README.md, it's used as that
# module's Doxygen mainpage automatically.
# -----------------------------------------------------------------------
function(_add_module_docs TARGET)
    if(NOT ENABLE_DOXYGEN)
        return()
    endif()

    set(DOXYGEN_OUTPUT_DIRECTORY "${DOCS_OUTPUT_DIR}/${TARGET}")
    set(DOXYGEN_PROJECT_NAME "${TARGET}")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/README.md")
        set(DOXYGEN_USE_MDFILE_AS_MAINPAGE "${CMAKE_CURRENT_SOURCE_DIR}/README.md")
    else()
        unset(DOXYGEN_USE_MDFILE_AS_MAINPAGE)
    endif()

    doxygen_add_docs(docs_${TARGET}
        "${CMAKE_CURRENT_SOURCE_DIR}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        COMMENT "Generating documentation for module '${TARGET}'"
    )
    set_target_properties(docs_${TARGET} PROPERTIES EXCLUDE_FROM_ALL TRUE)
    add_dependencies(docs docs_${TARGET})

    set_property(GLOBAL APPEND PROPERTY PMN_DOC_MODULES ${TARGET})
endfunction()

# -----------------------------------------------------------------------
# _write_docs_index(OUTPUT_DIR): call once, after every module has been
# discovered, to write a plain landing page at OUTPUT_DIR/index.html
# linking to each module's own generated docs -- so "where do I start
# reading" has one obvious answer regardless of how many modules exist.
# -----------------------------------------------------------------------
function(_write_docs_index OUTPUT_DIR)
    if(NOT ENABLE_DOXYGEN)
        return()
    endif()
    file(MAKE_DIRECTORY "${OUTPUT_DIR}")
    get_property(_pmn_doc_modules GLOBAL PROPERTY PMN_DOC_MODULES)
    list(SORT _pmn_doc_modules)
    set(_pmn_doc_links "")
    foreach(_pmn_mod ${_pmn_doc_modules})
        string(APPEND _pmn_doc_links "    <li><a href=\"${_pmn_mod}/html/index.html\">${_pmn_mod}</a></li>\n")
    endforeach()
    file(WRITE "${OUTPUT_DIR}/index.html" "<!DOCTYPE html>
<html>
<head><meta charset=\"utf-8\"><title>${PROJECT_NAME} -- module documentation</title></head>
<body>
  <h1>${PROJECT_NAME} module documentation</h1>
  <ul>
${_pmn_doc_links}  </ul>
</body>
</html>
")
endfunction()
