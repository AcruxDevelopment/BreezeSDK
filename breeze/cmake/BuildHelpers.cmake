# =============================================================================
# BuildHelpers.cmake
#
# Reusable, project-agnostic build machinery: module discovery, per-target
# compiler/RPATH settings, and the module-registration macros (add_lib_module,
# add_objects_module, add_exe_module, add_test_module, add_example_module) that
# a module's own CMakeLists.txt calls.
#
# This file is meant to change rarely and hold nothing project-specific.
# New targets should not need edits here, or in Breeze.cmake --
# see the "Module discovery" section of Breeze.cmake and the per-module
# CMakeLists.txt convention described there.
#
# Expects the including file (Breeze.cmake) to have already set (from project()
# and project/Configuration.cmake): PROJECT_NAME, PROJECT_VERSION,
# PROJECT_CODE_NAME. Multiplatform: MSVC/WIN32 branches guard the
# Windows-only paths; everything else is generic.
# =============================================================================

include_guard(GLOBAL)

# -----------------------------------------------------------------------
# all_tests / all_examples -- aggregate targets so groups can be built
# without CMake target-name collisions:
#   cmake --build . --target all_tests
#   cmake --build . --target all_examples
#
# enable_testing() is required for add_test_module()'s add_test() calls to
# actually be discoverable by ctest -- without it, tests build fine but
# `ctest` reports "No tests were found" with no error anywhere else.
# -----------------------------------------------------------------------
enable_testing()
add_custom_target(all_tests    COMMENT "Build all test targets")
add_custom_target(all_examples COMMENT "Build all example targets")

# -----------------------------------------------------------------------
# _discover_module_subdirectories(ROOT_DIR): add_subdirectory() every
# immediate child of ROOT_DIR that contains its own CMakeLists.txt.
#
# This is the whole mechanism behind "no root edits to add a module": drop
# a new directory with a one-line CMakeLists.txt under one of the known
# module roots (source/ for libraries and apps, source/tests/ or
# source/examples/ for tests and examples) and it is picked up automatically.
# CONFIGURE_DEPENDS means the *next build* reconfigures on its own after a
# module directory is added or removed -- no manual `cmake` re-run needed.
#
# Order between add_subdirectory() calls does not matter for correctness:
# CMake resolves target_link_libraries() names against the whole project
# at generate time, not sequentially, so a module may DEPENDS on a module
# discovered later (verified empirically -- this isn't a guess).
#
# A macro (not a function) so add_subdirectory() behaves exactly as if it
# were called directly from the caller -- no extra scope layer involved.
# -----------------------------------------------------------------------
macro(_discover_module_subdirectories ROOT_DIR)
    if(IS_DIRECTORY "${ROOT_DIR}")
        file(GLOB _pmn_module_candidates CONFIGURE_DEPENDS LIST_DIRECTORIES true "${ROOT_DIR}/*")
        foreach(_pmn_candidate ${_pmn_module_candidates})
            if(IS_DIRECTORY "${_pmn_candidate}" AND EXISTS "${_pmn_candidate}/CMakeLists.txt")
                add_subdirectory("${_pmn_candidate}")
            endif()
        endforeach()
    endif()
endmacro()

# -----------------------------------------------------------------------
# _apply_compile_options: per-target warning flags.
# MSVC path  : /W4 (high warnings) + /permissive- (strict conformance).
# GCC/Clang  : -Wall -Wextra -Wpedantic.
# -----------------------------------------------------------------------
function(_apply_compile_options TARGET)
    if(MSVC)
        target_compile_options(${TARGET} PRIVATE /W4 /permissive-)
    else()
        target_compile_options(${TARGET} PRIVATE -Wall -Wextra -Wpedantic)
    endif()
endfunction()

# -----------------------------------------------------------------------
# _apply_rpath: RPATH is an ELF (Linux) and Mach-O (macOS) concept; skip
# entirely on Windows. Callers spell "relative to this binary" the ELF way,
# $ORIGIN[/..]; Mach-O's loader has never heard of that token -- its
# equivalent is @loader_path -- so it is translated here, once, instead of
# every call site having to know which platform it's on. (For an executable
# @loader_path is the executable's own directory; for a library, the
# library's. That is exactly the layout this project uses: everything
# lands flat in bin/, tests and examples one level down in bin/tests and
# bin/examples.)
# -----------------------------------------------------------------------
function(_apply_rpath TARGET RPATH_VAL)
    if(NOT WIN32)
        if(APPLE)
            string(REPLACE "$ORIGIN" "@loader_path" RPATH_VAL "${RPATH_VAL}")
        endif()
        set_target_properties(${TARGET} PROPERTIES
            BUILD_RPATH   "${RPATH_VAL}"
            INSTALL_RPATH "${RPATH_VAL}"
        )
    endif()
endfunction()

# -----------------------------------------------------------------------
# _set_output_dirs(TARGET RUNTIME_DIR [LIBRARY_DIR]):
#
# Breeze.cmake sets CMAKE_RUNTIME_OUTPUT_DIRECTORY_<CONFIG> /
# CMAKE_LIBRARY_OUTPUT_DIRECTORY_<CONFIG> globally (once, near the top) so
# every target defaults to the flat bin/ layout. That also means every
# new target's per-config RUNTIME_OUTPUT_DIRECTORY_<CONFIG> /
# LIBRARY_OUTPUT_DIRECTORY_<CONFIG> property is pre-populated at creation
# time -- and a per-config property always wins over the plain
# (config-independent) one. So a module that needs a *different* output
# directory (tests -> bin/tests, examples -> bin/examples) must override
# the per-config properties too, or the override silently has no effect.
# This helper does both in one place.
# -----------------------------------------------------------------------
function(_set_output_dirs TARGET RUNTIME_DIR)
    set(_library_dir "${RUNTIME_DIR}")
    if(ARGC GREATER 2)
        set(_library_dir "${ARGV2}")
    endif()
    set_target_properties(${TARGET} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${RUNTIME_DIR}"
        LIBRARY_OUTPUT_DIRECTORY "${_library_dir}"
    )
    foreach(_cfg Debug Release RelWithDebInfo MinSizeRel)
        string(TOUPPER "${_cfg}" _CFG)
        set_target_properties(${TARGET} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY_${_CFG} "${RUNTIME_DIR}"
            LIBRARY_OUTPUT_DIRECTORY_${_CFG} "${_library_dir}"
        )
    endforeach()
endfunction()

# -----------------------------------------------------------------------
# _copy_mingw_runtime_dlls(TARGET): copies PMN_MINGW_RUNTIME_DLLS (computed
# once in Breeze.cmake's "MinGW runtime linking" section) next to
# TARGET's own built binary, in the build tree, so it runs without a
# manual step. install()-time placement is the matching
# install(FILES ...) in Breeze.cmake's "install" section. A no-op
# whenever PMN_MINGW_RUNTIME_DLLS is empty (every non-MinGW platform, or
# a MinGW toolchain where none of the candidate DLLs were found).
#
# Called for every SHARED module unconditionally (source/Core's
# core_lib/demo_core.dll always uses the dynamic runtime -- see the
# "MinGW runtime linking" comment for why making it static too isn't an
# option), and for EXECUTABLE/test/example targets only when
# PMN_MINGW_STATIC_RUNTIME is OFF (the default): with it ON those are
# statically linked and don't need these DLLs, so the caller skips this
# call entirely rather than copying files nothing imports.
# -----------------------------------------------------------------------
function(_copy_mingw_runtime_dlls TARGET)
    if(MINGW AND PMN_MINGW_RUNTIME_DLLS)
        add_custom_command(TARGET ${TARGET} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${PMN_MINGW_RUNTIME_DLLS} "$<TARGET_FILE_DIR:${TARGET}>"
            COMMENT "Copying MinGW runtime DLLs next to ${TARGET}"
            VERBATIM
        )
    endif()
endfunction()

# -----------------------------------------------------------------------
# _copy_target_runtime_dlls(TARGET): on Windows (any compiler -- MSVC,
# clang-cl, or MinGW), copies every SHARED-library dependency's own .dll
# next to TARGET's binary, via CMake's TARGET_RUNTIME_DLLS generator
# expression. This is the OTHER half of running on Windows that
# _copy_mingw_runtime_dlls doesn't cover: that one only bundles the
# compiler's OWN runtime (libgcc/libstdc++/winpthread); this one bundles
# this project's SHARED modules (core_lib/demo_core.dll, and anything
# else a module's own CMakeLists.txt declares SHARED).
#
# Needed specifically for add_test_module/add_example_module: they land
# one directory below the primary modules (bin/tests, bin/examples),
# with an RPATH of "$ORIGIN/.." for the ELF/Mach-O builds where that
# works (see _apply_rpath) -- but Windows has no equivalent of a
# *relative*, directory-based DLL search path, so a test or example that
# depends on a SHARED module built by this project needs that DLL
# copied into ITS OWN directory to run at all, not just the primary
# one. (The primary modules -- add_exe_module -- don't need this: they
# already land in the SAME flat bin/ directory as every SHARED module,
# so they already find it there.) Confirmed directly by cross-building
# for windows-x64-mingw64 and running the result under Wine: a test
# depending on core_lib fails to start (STATUS_DLL_NOT_FOUND,
# "libdemo_core.dll ... not found") without this.
#
# Delegates the actual copy to CopyRuntimeDlls.cmake rather than calling
# `cmake -E copy_if_different` directly, because that fails the whole
# build the moment TARGET_RUNTIME_DLLS is empty -- the common case for
# any test/example that doesn't depend on a SHARED module -- and
# `cmake -E copy_if_different <dest-only, no sources>` is exactly that:
# zero sources. See that script for the confirmed failure and the
# one-line `if(FILES)` fix.
# -----------------------------------------------------------------------
function(_copy_target_runtime_dlls TARGET)
    if(WIN32)
        add_custom_command(TARGET ${TARGET} POST_BUILD
            COMMAND ${CMAKE_COMMAND}
                -DDEST=$<TARGET_FILE_DIR:${TARGET}>
                "-DFILES=$<TARGET_RUNTIME_DLLS:${TARGET}>"
                -P "${PMN_BREEZE_CMAKE_DIR}/CopyRuntimeDlls.cmake"
            COMMENT "Copying ${TARGET}'s own SHARED-library dependencies next to it"
            VERBATIM
        )
    endif()
endfunction()

# -----------------------------------------------------------------------
# _register_executable_target(TARGET): tracks every executable module
# (exe/test/example) in a global property so _write_module_manifest()
# can find them all without anything needing to know their names ahead
# of time.
# -----------------------------------------------------------------------
function(_register_executable_target TARGET)
    set_property(GLOBAL APPEND PROPERTY PMN_EXECUTABLE_TARGETS ${TARGET})
endfunction()

# -----------------------------------------------------------------------
# _register_module_target(CATEGORY TARGET): tracks a target under
# CATEGORY (PRIMARY, TEST, or EXAMPLE) in a global property so
# Breeze.cmake's install() rules can be generated from whatever modules
# actually got discovered, instead of a hardcoded target list that would
# need editing every time a module is added or removed.
# -----------------------------------------------------------------------
function(_register_module_target CATEGORY TARGET)
    set_property(GLOBAL APPEND PROPERTY PMN_MODULE_TARGETS_${CATEGORY} ${TARGET})
endfunction()

# -----------------------------------------------------------------------
# _write_module_manifest(OUTPUT_DIR): call once, after every module has
# been discovered, to emit "<target-name>=<absolute-path-to-binary>"
# lines for every executable module into
# OUTPUT_DIR/module_manifest-<CONFIG>.txt.
#
# breeze/scripts/run.sh / run.bat read this file to resolve a CMake target name to its
# actual executable path -- so they never hardcode per-module paths and
# never need editing when a module is added, removed, or renamed.
# $<CONFIG> is part of the filename because file(GENERATE) requires that
# for content (like $<TARGET_FILE:...>) that can differ per build
# configuration under a multi-config generator (e.g. Ninja Multi-Config).
# -----------------------------------------------------------------------
function(_write_module_manifest OUTPUT_DIR)
    get_property(_pmn_targets GLOBAL PROPERTY PMN_EXECUTABLE_TARGETS)
    set(_manifest_content "")
    foreach(_t ${_pmn_targets})
        string(APPEND _manifest_content "${_t}=$<TARGET_FILE:${_t}>\n")
    endforeach()
    file(GENERATE
        OUTPUT "${OUTPUT_DIR}/module_manifest-$<CONFIG>.txt"
        CONTENT "${_manifest_content}"
    )
endfunction()

# -----------------------------------------------------------------------
# _finalize_module_target(TARGET MODULE_NAME [OUTPUT_NAME name] [DEPENDS ...])
#
# The tail every module macro below shares: identity compile definitions,
# warning flags, OUTPUT_NAME, and DEPENDS linking. Centralized so all four
# macros stay in lockstep -- edit once here instead of four times.
# Re-parses the caller's raw ARGN, so it's safe to call as
# _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN}) even though
# ARGN also contains keywords (TYPE, EXTRA_SOURCES, ...) this function
# doesn't know about -- those are simply ignored.
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# _finalize_module_target(TARGET MODULE_NAME [OUTPUT_NAME name] [DEPENDS ...]
#                          [NO_DOCS])
#
# The tail every module macro below shares: identity compile definitions,
# warning flags, OUTPUT_NAME, DEPENDS linking, and an automatic per-module
# Doxygen target (see breeze/cmake/Documentation.cmake) unless NO_DOCS is given.
# Centralized so all four macros stay in lockstep -- edit once here
# instead of four times. Re-parses the caller's raw ARGN, so it's safe to
# call as _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN}) even
# though ARGN also contains keywords (TYPE, EXTRA_SOURCES, ...) this
# function doesn't know about -- those are simply ignored.
# -----------------------------------------------------------------------
function(_finalize_module_target TARGET MODULE_NAME)
    cmake_parse_arguments(FIN "NO_DOCS" "OUTPUT_NAME" "DEPENDS" ${ARGN})

    # Every module and what it DEPENDS on, for _resolve_object_modules(): object
    # modules can't be told apart from libraries here -- the module they name
    # may not have been discovered yet -- so that is decided once all exist.
    set_property(GLOBAL APPEND PROPERTY PMN_ALL_MODULES ${TARGET})
    set_property(GLOBAL PROPERTY PMN_DEPENDS_${TARGET} "${FIN_DEPENDS}")

    target_compile_definitions(${TARGET} PRIVATE
        $<$<CONFIG:Debug>:DEBUG>
        MODULE_NAME="${MODULE_NAME}"
        PROJECT_NAME="${PROJECT_NAME}"
        PROJECT_NAME_CODE="${PROJECT_CODE_NAME}"
        PROJECT_VER="${PROJECT_VERSION}"
    )
    _apply_compile_options(${TARGET})

    # An objects module has no file to name: for it OUTPUT_NAME is only the name
    # MODULE_NAME carries (the library it is a piece of, usually).
    get_target_property(_pmn_target_type ${TARGET} TYPE)
    if(FIN_OUTPUT_NAME AND NOT _pmn_target_type STREQUAL "OBJECT_LIBRARY")
        set_target_properties(${TARGET} PROPERTIES OUTPUT_NAME ${FIN_OUTPUT_NAME})
    endif()
    if(FIN_DEPENDS)
        target_link_libraries(${TARGET} PRIVATE ${FIN_DEPENDS})
    endif()
    if(NOT FIN_NO_DOCS)
        _add_module_docs(${TARGET})
    endif()
endfunction()

# =============================================================================
# add_lib_module(NAME [TYPE STATIC|SHARED] [OUTPUT_NAME name] [DEPENDS ...]
#                 [EXTRA_SOURCES ...] [NO_DOCS])
#
# Called from a library module's own CMakeLists.txt (e.g. source/Core/CMakeLists.txt).
# Sources/headers are globbed relative to that module's own directory:
# src/*.cpp and include/*.h(pp) underneath it. TYPE picks STATIC or SHARED
# for this module only; omit it to use the project-wide default
# (BUILD_SHARED_LIBS -- set in Breeze.cmake's OPTIONS section, or pass
# -DBUILD_SHARED_LIBS=ON at configure time).
#
# Headers are globbed in purely so they show up in IDE project trees --
# CMake never compiles headers, so this is inert for the actual build.
# =============================================================================
macro(add_lib_module NAME)
    cmake_parse_arguments(ARG "" "OUTPUT_NAME;TYPE" "DEPENDS;EXTRA_SOURCES" ${ARGN})

    if(ARG_OUTPUT_NAME)
        set(_MODULE_NAME ${ARG_OUTPUT_NAME})
    else()
        set(_MODULE_NAME ${NAME})
    endif()

    if(ARG_TYPE)
        set(_LIB_TYPE ${ARG_TYPE})
    elseif(BUILD_SHARED_LIBS)
        set(_LIB_TYPE SHARED)
    else()
        set(_LIB_TYPE STATIC)
    endif()
    if(NOT _LIB_TYPE MATCHES "^(STATIC|SHARED)$")
        message(FATAL_ERROR "add_lib_module(${NAME}): TYPE must be STATIC or SHARED, got '${_LIB_TYPE}'")
    endif()

    file(GLOB_RECURSE ${NAME}_SOURCES CONFIGURE_DEPENDS src/*.cpp)
    file(GLOB_RECURSE ${NAME}_HEADERS CONFIGURE_DEPENDS include/*.h include/*.hpp)

    add_library(${NAME} ${_LIB_TYPE} ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    target_include_directories(${NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

    if(_LIB_TYPE STREQUAL "STATIC")
        # Keep static libs relocatable in case they end up linked into a
        # shared library or PIE executable later.
        set_target_properties(${NAME} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    else()
        # LIBRARY_OUTPUT_DIRECTORY controls .so placement on Linux.
        # RUNTIME_OUTPUT_DIRECTORY controls .dll placement on Windows.
        # WINDOWS_EXPORT_ALL_SYMBOLS auto-generates a .def file so all
        # public symbols are exported without __declspec(dllexport).
        # Remove if you prefer explicit visibility macros instead.
        _set_output_dirs(${NAME} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}" "${CMAKE_BINARY_DIR}/${LIBRARY_OUTPUT_SUBDIR}")
        set_target_properties(${NAME} PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

        # A SHARED module always keeps the dynamic MinGW runtime -- see
        # Breeze.cmake's "MinGW runtime linking" comment for why it's
        # never a candidate for PMN_MINGW_STATIC_RUNTIME -- so this call
        # is unconditional, unlike the EXECUTABLE-producing macros below.
        _copy_mingw_runtime_dlls(${NAME})
    endif()

    _register_module_target(PRIMARY ${NAME})
    _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN})
endmacro()

# Back-compat wrappers for the old two-macro spelling.
# Prefer add_lib_module(... TYPE STATIC|SHARED) directly in new code.
macro(add_static_lib_module NAME)
    add_lib_module(${NAME} TYPE STATIC ${ARGN})
endmacro()
macro(add_shared_lib_module NAME)
    add_lib_module(${NAME} TYPE SHARED ${ARGN})
endmacro()

# =============================================================================
# add_objects_module(NAME [OUTPUT_NAME name] [DEPENDS ...] [EXTRA_SOURCES ...] [NO_DOCS])
#
# Called from an objects module's own CMakeLists.txt (e.g. source/CoreMath/CMakeLists.txt).
# An OBJECT library: its sources are compiled, and that is all -- no archive, no
# DLL, nothing in bin/ or lib/. Name it in the DEPENDS of a library, an
# executable, a test, an example, or another objects module, and its object
# files become part of that target. That is what makes it the way to split
# one big library into pieces: each piece is a module of its own (own
# directory, own include/, built and tested on its own), and the library
# that is left is one line naming them.
#
#   source/CoreMath/CMakeLists.txt   add_objects_module(core_math)
#   source/CoreIo/CMakeLists.txt     add_objects_module(core_io DEPENDS core_math)
#   source/Core/CMakeLists.txt       add_lib_module(core DEPENDS core_io)
#
# Sources/headers are globbed like a library's: src/*.cpp and include/*.h(pp)
# under the module's own directory. include/ is public: whoever takes the
# objects sees the headers -- and for a library, so do ITS consumers (see
# _resolve_object_modules below), because the headers of the pieces are the
# library's headers. Keep a piece's private headers in src/.
#
# OUTPUT_NAME names nothing here -- there is no file -- but is what the
# MODULE_NAME definition carries: pass the library's name so the pieces
# of one library all identify as it.
#
# Not installed, not run, not in the module manifest: the objects live on
# inside whatever took them. Always compiled position-independent, since
# they may land in a shared library.
# =============================================================================
macro(add_objects_module NAME)
    cmake_parse_arguments(ARG "" "OUTPUT_NAME" "DEPENDS;EXTRA_SOURCES" ${ARGN})

    if(ARG_OUTPUT_NAME)
        set(_MODULE_NAME ${ARG_OUTPUT_NAME})
    else()
        set(_MODULE_NAME ${NAME})
    endif()

    file(GLOB_RECURSE ${NAME}_SOURCES CONFIGURE_DEPENDS src/*.cpp)
    file(GLOB_RECURSE ${NAME}_HEADERS CONFIGURE_DEPENDS include/*.h include/*.hpp)

    add_library(${NAME} OBJECT ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    target_include_directories(${NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
    set_target_properties(${NAME} PROPERTIES POSITION_INDEPENDENT_CODE ON)

    # Its own category: install() (Breeze.cmake) only takes PRIMARY, and an
    # OBJECT library has nothing of its own to install.
    _register_module_target(OBJECTS ${NAME})
    _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN})
endmacro()

# -----------------------------------------------------------------------
# _resolve_object_modules(): call once, after every module has been
# discovered (Breeze.cmake does).
#
# CMake links an OBJECT library's objects into the target that names it,
# exactly once -- and no further. A piece that DEPENDS on another piece does
# not carry that piece's objects along, so a library naming only the first
# one fails at link time with undefined references. And a library that has
# taken a piece's objects does not pass the piece's headers on to its own
# consumers, unless it links the piece PUBLIC.
#
# So, for every module target, the objects modules it names -- directly, or
# through other objects modules -- are collected, and each is linked:
#
#   * library (static/shared) or objects module: PUBLIC. Objects go into it;
#     its consumers see the pieces' include/ and compile definitions, and
#     get no second copy of the objects -- they are inside it already.
#   * executable (app, test, example): PRIVATE. Nothing consumes it.
#
# Only objects modules are followed. A module that is an ordinary library
# keeps whatever it has inside it; what a piece links (a static library, say)
# is reached by CMake on its own at the final link.
#
# Done here and not in the macros because the macros can't know what a
# name in DEPENDS is: modules are discovered in directory order, and the
# one named may not exist yet.
# -----------------------------------------------------------------------
function(_resolve_object_modules)
    get_property(_pmn_all_modules GLOBAL PROPERTY PMN_ALL_MODULES)
    foreach(_pmn_module IN LISTS _pmn_all_modules)
        get_target_property(_pmn_module_type ${_pmn_module} TYPE)
        get_property(_pmn_direct GLOBAL PROPERTY PMN_DEPENDS_${_pmn_module})

        set(_pmn_queue "${_pmn_direct}")
        set(_pmn_seen "")
        set(_pmn_pieces "")
        while(NOT "${_pmn_queue}" STREQUAL "")
            list(POP_FRONT _pmn_queue _pmn_name)
            if(_pmn_name IN_LIST _pmn_seen)
                continue()
            endif()
            list(APPEND _pmn_seen ${_pmn_name})
            if(NOT TARGET ${_pmn_name})
                continue()
            endif()
            get_target_property(_pmn_name_type ${_pmn_name} TYPE)
            if(NOT _pmn_name_type STREQUAL "OBJECT_LIBRARY")
                continue()
            endif()
            if(_pmn_name STREQUAL _pmn_module)
                message(FATAL_ERROR
                    "The objects module '${_pmn_module}' depends on itself, through the "
                    "objects modules it names (directly or not) in DEPENDS.")
            endif()
            list(APPEND _pmn_pieces ${_pmn_name})
            get_property(_pmn_more GLOBAL PROPERTY PMN_DEPENDS_${_pmn_name})
            list(APPEND _pmn_queue ${_pmn_more})
        endwhile()

        foreach(_pmn_piece IN LISTS _pmn_pieces)
            if(_pmn_module_type STREQUAL "EXECUTABLE")
                # Already linked PRIVATE when named directly (_finalize_module_target).
                if(NOT _pmn_piece IN_LIST _pmn_direct)
                    target_link_libraries(${_pmn_module} PRIVATE ${_pmn_piece})
                endif()
            else()
                target_link_libraries(${_pmn_module} PUBLIC ${_pmn_piece})
            endif()
        endforeach()
    endforeach()
endfunction()

# =============================================================================
# add_exe_module(NAME [OUTPUT_NAME name] [DEPENDS ...] [EXTRA_SOURCES ...] [NO_DOCS])
#
# Called from an app module's own CMakeLists.txt (e.g. HelloApp/CMakeLists.txt).
# Sources/headers are globbed relative to that module's own directory:
# *.cpp and include/*.h(pp) underneath it.
# =============================================================================
macro(add_exe_module NAME)
    cmake_parse_arguments(ARG "" "OUTPUT_NAME" "DEPENDS;EXTRA_SOURCES" ${ARGN})

    if(ARG_OUTPUT_NAME)
        set(_MODULE_NAME ${ARG_OUTPUT_NAME})
    else()
        set(_MODULE_NAME ${NAME})
    endif()

    file(GLOB_RECURSE ${NAME}_SOURCES CONFIGURE_DEPENDS *.cpp)
    file(GLOB_RECURSE ${NAME}_HEADERS CONFIGURE_DEPENDS include/*.h include/*.hpp)

    add_executable(${NAME} ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    target_include_directories(${NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
    _set_output_dirs(${NAME} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}")
    _apply_rpath(${NAME} "$ORIGIN")
    _register_module_target(PRIMARY ${NAME})
    _register_executable_target(${NAME})
    # Skipped when PMN_MINGW_STATIC_RUNTIME is ON: that link option (set in
    # Breeze.cmake) makes this target self-contained instead, and these
    # DLLs would be unused files sitting next to it. See that option's own
    # comment for why OFF (dynamic, copied here) is the safe default.
    if(NOT PMN_MINGW_STATIC_RUNTIME)
        _copy_mingw_runtime_dlls(${NAME})
    endif()

    _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN})
endmacro()

# =============================================================================
# add_test_module(NAME [OUTPUT_NAME name] [DEPENDS ...] [EXTRA_SOURCES ...] [NO_DOCS])
#
# Called from a test module's own CMakeLists.txt (e.g. source/tests/mytest/CMakeLists.txt).
# Lands in bin/tests/, so shared-lib deps one level up need $ORIGIN/...
# EXCLUDE_FROM_ALL keeps it out of the default build; BUILD_TESTS opts it
# back in.
# =============================================================================
macro(add_test_module NAME)
    cmake_parse_arguments(ARG "" "OUTPUT_NAME" "DEPENDS;EXTRA_SOURCES" ${ARGN})

    if(ARG_OUTPUT_NAME)
        set(_MODULE_NAME ${ARG_OUTPUT_NAME})
    else()
        set(_MODULE_NAME ${NAME})
    endif()

    file(GLOB_RECURSE ${NAME}_SOURCES CONFIGURE_DEPENDS *.cpp)
    file(GLOB_RECURSE ${NAME}_HEADERS CONFIGURE_DEPENDS include/*.h include/*.hpp)

    if(BUILD_TESTS)
        add_executable(${NAME} ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    else()
        add_executable(${NAME} EXCLUDE_FROM_ALL ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    endif()
    target_include_directories(${NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    _set_output_dirs(${NAME} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}/tests")
    _apply_rpath(${NAME} "$ORIGIN/..")
    _register_module_target(TEST ${NAME})
    _register_executable_target(${NAME})
    # See add_exe_module's identical guard on the first call: skipped
    # under PMN_MINGW_STATIC_RUNTIME, which makes this target
    # self-contained instead. The second call is unconditional and
    # WIN32-wide (not just MinGW): bin/tests/ is a different directory
    # from bin/, so any SHARED module this test depends on (this
    # project's core_lib included) needs its own .dll copied here too --
    # see _copy_target_runtime_dlls's own comment for why a *different*
    # mechanism than the one above is needed for that.
    if(NOT PMN_MINGW_STATIC_RUNTIME)
        _copy_mingw_runtime_dlls(${NAME})
    endif()
    _copy_target_runtime_dlls(${NAME})

    _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN})

    add_test(NAME ${NAME} COMMAND ${NAME})
    add_dependencies(all_tests ${NAME})
endmacro()

# =============================================================================
# add_example_module(NAME [OUTPUT_NAME name] [DEPENDS ...] [EXTRA_SOURCES ...] [NO_DOCS])
#
# Called from an example module's own CMakeLists.txt (e.g. source/examples/myexample/CMakeLists.txt).
# Same bin/examples/ + $ORIGIN/.. layout as tests.
# =============================================================================
macro(add_example_module NAME)
    cmake_parse_arguments(ARG "" "OUTPUT_NAME" "DEPENDS;EXTRA_SOURCES" ${ARGN})

    if(ARG_OUTPUT_NAME)
        set(_MODULE_NAME ${ARG_OUTPUT_NAME})
    else()
        set(_MODULE_NAME ${NAME})
    endif()

    file(GLOB_RECURSE ${NAME}_SOURCES CONFIGURE_DEPENDS *.cpp)
    file(GLOB_RECURSE ${NAME}_HEADERS CONFIGURE_DEPENDS include/*.h include/*.hpp)

    if(BUILD_EXAMPLES)
        add_executable(${NAME} ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    else()
        add_executable(${NAME} EXCLUDE_FROM_ALL ${${NAME}_SOURCES} ${${NAME}_HEADERS} ${ARG_EXTRA_SOURCES})
    endif()
    target_include_directories(${NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    _set_output_dirs(${NAME} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}/examples")
    _apply_rpath(${NAME} "$ORIGIN/..")
    _register_module_target(EXAMPLE ${NAME})
    _register_executable_target(${NAME})
    # See add_test_module's identical pair of calls and comment just above.
    if(NOT PMN_MINGW_STATIC_RUNTIME)
        _copy_mingw_runtime_dlls(${NAME})
    endif()
    _copy_target_runtime_dlls(${NAME})

    _finalize_module_target(${NAME} ${_MODULE_NAME} ${ARGN})

    add_dependencies(all_examples ${NAME})
endmacro()
