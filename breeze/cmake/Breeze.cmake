# =============================================================================
# breeze/cmake/Breeze.cmake
#
# The build system itself: what the template contributes to a project, from
# the C++ standard and the output directories to module discovery and the
# install rules. Included by the project's CMakeLists.txt right after
# project(); the project's own settings are in project/Configuration.cmake (read
# here, through CMakeLists.txt having included it). Replacing breeze/ updates
# the template without touching either.
# =============================================================================

cmake_minimum_required(VERSION 3.25)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# This project's settings (PROJECT_CODE_NAME, DEFAULT_BUILD_TYPE, the output paths
# and the bin/lib subdirectory names) come from project/Configuration.cmake --
# already included by CMakeLists.txt, before project(); this is a no-op unless
# something includes this file on its own. The target selection
# (DIST_TARGET/PLATFORM/ARCHITECTURE/COMPILER_ID) is TargetSelection.cmake: it
# needs real compiler detection, which is why it comes after project(), and
# everything below depends on it. Edit project/Configuration.cmake, or pass
# -D<NAME>=... at configure time, rather than hardcoding a value it already owns
# anywhere else in this project, scripts included.
# Where the template is, and where the project that uses it is -- found from this
# file's own location rather than from CMAKE_SOURCE_DIR, which is the outermost
# project's when this one is embedded with add_subdirectory().
set(PMN_BREEZE_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}")
get_filename_component(PMN_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${PMN_PROJECT_ROOT}/project/Configuration.cmake")

# The contract with project/Configuration.cmake: these are the settings the template
# reads. A project file from an older template version may lack one that a newer
# version added -- say which, instead of failing somewhere downstream on an empty value.
foreach(_pmn_setting
        PROJECT_CODE_NAME DEFAULT_BUILD_TYPE
        OUT_DIR BUILD_OUTPUT_DIR INSTALL_OUTPUT_DIR DOCS_OUTPUT_DIR DIST_OUTPUT_DIR
        TOOLCACHE_DIR COMPILE_COMMANDS_DESTINATION
        RUNTIME_OUTPUT_SUBDIR LIBRARY_OUTPUT_SUBDIR ARCHIVE_OUTPUT_SUBDIR)
    if(NOT DEFINED ${_pmn_setting})
        message(FATAL_ERROR
            "project/Configuration.cmake does not define ${_pmn_setting}, which this version "
            "of breeze/ needs. Add it: a fresh copy of the template's project/Configuration.cmake "
            "shows the default.")
    endif()
endforeach()
include("${CMAKE_CURRENT_LIST_DIR}/TargetSelection.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/GitignoreSync.cmake")

# The language standard is the project's choice (project/Configuration.cmake);
# requiring it and turning compiler extensions off is the template's policy.
if(NOT DEFINED PROJECT_CXX_STANDARD)
    set(PROJECT_CXX_STANDARD 20)
endif()
set(CMAKE_CXX_STANDARD ${PROJECT_CXX_STANDARD})
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)


# This project uses C++20 but not C++20 modules. CMake >= 3.28 nevertheless
# assumes C++20 sources might `import` modules and scans every one of them
# before compiling (policy CMP0155) -- in any directory whose own
# cmake_minimum_required is >= 3.28, which includes fetched dependencies
# like fmt even though this project's own minimum is lower. The scan needs
# a scanner tool (clang-scan-deps for Clang, which e.g. Ubuntu's plain
# `clang` package doesn't ship, so the build dies with
# "CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS-NOTFOUND") and adds a step to every
# compile. This variable is CMake's documented opt-out; it is inherited by
# every target created below, third-party ones included. If you start using
# modules, remove it (or set the CXX_SCAN_FOR_MODULES property on just the
# targets that need it).
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

# Every static library in the project gets built with -fPIC by default --
# including vendored/fetched ones, whose own CMakeLists.txt we don't
# control and can't rely on to opt in themselves. Without this, a static
# dependency (ours or third-party) fails to link the moment it ends up
# pulled into a SHARED module: "recompile with -fPIC". Cheap on every
# platform that matters here; add_lib_module's STATIC branch also sets
# this per-target as a belt-and-braces fallback.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# -------------------------------------------------------
# Generator guard -- require Ninja (single or multi-config)
# -------------------------------------------------------
if(NOT CMAKE_GENERATOR MATCHES "Ninja")
    message(WARNING
        "This project targets Ninja. "
        "Current generator: '${CMAKE_GENERATOR}'. "
        "Reconfigure with:  cmake -G Ninja  or  cmake -G \"Ninja Multi-Config\"")
endif()

# Single-config Ninja needs CMAKE_BUILD_TYPE at configure time.
# Ninja Multi-Config uses CMAKE_CONFIGURATION_TYPES instead (no BUILD_TYPE needed).
if(CMAKE_GENERATOR STREQUAL "Ninja")
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "${DEFAULT_BUILD_TYPE}" CACHE STRING
            "Build type (Debug|Release|RelWithDebInfo|MinSizeRel)" FORCE)
        message(STATUS "CMAKE_BUILD_TYPE not set -- defaulting to ${DEFAULT_BUILD_TYPE}")
    endif()
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        Debug Release RelWithDebInfo MinSizeRel)
endif()

# -------------------------------------------------------
# Flat output layout
# Multi-config generators (Ninja Multi-Config) append /<Config> by default.
# Override all four configs so both Ninja variants produce the same layout.
# Subdirectory names come from project/Configuration.cmake (RUNTIME_OUTPUT_SUBDIR
# etc.); the base directory is always CMAKE_BINARY_DIR, wherever -B points
# (breeze/scripts/build.sh uses out/build/<preset> -- see project/Configuration.cmake).
# -------------------------------------------------------
foreach(_cfg Debug Release RelWithDebInfo MinSizeRel)
    string(TOUPPER "${_cfg}" _CFG)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${LIBRARY_OUTPUT_SUBDIR}")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${ARCHIVE_OUTPUT_SUBDIR}")
endforeach()

# -------------------------------------------------------
# RPATH strategy
# By default CMake builds with a temporary RPATH and relinks at install time
# to embed the final one. Ninja on Linux with Clang does not support that
# relink step and will error out. Setting this ON tells CMake to embed the
# install RPATH at build time so no relink is ever needed.
# This is safe here because all our RPATHs are relative to the binary that
# carries them ($ORIGIN on Linux, @loader_path on macOS -- see
# _apply_rpath in breeze/cmake/BuildHelpers.cmake), so the same value is correct
# for both the build tree and the installed layout. Guarded to non-Windows
# since RPATH is an ELF/Mach-O concept only. (On macOS the same setting also
# spares CMake from rewriting load commands with install_name_tool at
# install time.)
# -------------------------------------------------------
if(NOT WIN32)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
endif()

# -------------------------------------------------------
# options
# -------------------------------------------------------
option(BUILD_TESTS      "Build test binaries"      OFF)
option(BUILD_EXAMPLES   "Build example binaries"   OFF)
option(INSTALL_TESTS    "Install test binaries"    OFF)
option(INSTALL_EXAMPLES "Install example binaries" OFF)

# Project-wide default for add_lib_module() when a module doesn't pass
# TYPE explicitly. This is CMake's own BUILD_SHARED_LIBS variable, so it
# also affects any third-party add_library() calls (FetchContent, etc.)
# that respect it. Override per-module with add_lib_module(... TYPE
# STATIC|SHARED ...), or globally with -DBUILD_SHARED_LIBS=ON.
option(BUILD_SHARED_LIBS "Build libraries as SHARED by default" OFF)

# INSTALL_* implies BUILD_* so targets exist when cmake --install runs
if(INSTALL_TESTS)
    set(BUILD_TESTS ON CACHE BOOL "" FORCE)
endif()
if(INSTALL_EXAMPLES)
    set(BUILD_EXAMPLES ON CACHE BOOL "" FORCE)
endif()

message(STATUS "BUILD_TESTS      = ${BUILD_TESTS}")
message(STATUS "BUILD_EXAMPLES   = ${BUILD_EXAMPLES}")
message(STATUS "BUILD_SHARED_LIBS (default lib TYPE) = ${BUILD_SHARED_LIBS}")

# -------------------------------------------------------
# Global compiler settings
#
# MSVC is TRUE for both cl.exe and clang-cl (windows-x64-msvc and
# windows-x64-clang-cl -- Clang targeting the MSVC ABI), so the outer
# block covers both with the flags they share. Two flags are cl.exe-only,
# though: clang-cl doesn't implement them and reports "argument unused
# during compilation" for every translation unit, so they're gated on the
# compiler ID (MSVC == cl.exe; clang-cl reports Clang) rather than on
# the MSVC variable.
#
# Shared by cl.exe and clang-cl:
#   /EHsc            -- standard C++ exception handling
#   /utf-8           -- UTF-8 source + execution charset
# cl.exe only:
#   /MP              -- parallel file compilation within one compiler
#                       invocation (Ninja also parallelizes across
#                       invocations; clang-cl ignores this)
#   /Zc:preprocessor -- conformant preprocessor (fixes __VA_ARGS__ etc.);
#                       clang's preprocessor is always conformant
# -------------------------------------------------------
if(MSVC)
    add_compile_options(/EHsc /utf-8)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        add_compile_options(/MP /Zc:preprocessor)
    endif()
endif()

# -------------------------------------------------------
# MinGW runtime linking (windows-x86-mingw32 / windows-x64-mingw64)
#
# A MinGW build dynamically links libgcc/libstdc++/(on some toolchains)
# libwinpthread by default, which then have to ship alongside every
# binary that needs them -- easy to forget, and the exact DLL names
# differ between mingw32 and mingw64 and between exception models (SEH
# on x86_64; DWARF-2 or SJLJ on i686). PMN_MINGW_RUNTIME_DLLS below
# resolves the actual files by asking the compiler rather than
# hardcoding names (-print-file-name=NAME echoes NAME back unchanged if
# it can't find it, which is how "not applicable to this toolchain" is
# detected), and BuildHelpers.cmake's _copy_mingw_runtime_dlls() copies
# them next to every EXECUTABLE/SHARED/test/example target that needs
# them, in the build tree and at install time (the "install" section
# below) -- so nothing here needs a manual step. MINGW is CMake's
# built-in equivalent of this project's own COMPILER_ID being "mingw32"
# or "mingw64".
#
# PMN_MINGW_STATIC_RUNTIME (default OFF) is what this project used to do
# unconditionally: link every EXECUTABLE against a private, static copy
# of libgcc/libstdc++/winpthread instead (-static-libgcc -static-libstdc++
# -static -lwinpthread -- EXECUTABLE targets only, via a generator
# expression, since applying it to a SHARED target collides with
# WINDOWS_EXPORT_ALL_SYMBOLS: a statically-linked unwinder re-exported
# from the DLL's own import library and a second static copy in the EXE
# both trying to define `_Unwind_Resume` is a link error). It trades
# shipping the runtime DLLs for a standalone .exe -- which is safe only
# as long as no EXECUTABLE built this way ALSO links a MinGW SHARED
# module (this project always has one -- core_lib/demo_core.dll) THAT
# PASSES AN STL TYPE ACROSS THAT BOUNDARY BY VALUE. core_lib's
# std::string makeGreeting(...) does exactly that: an executable with
# its own private, statically-linked libstdc++ has its own private
# allocator, separate from the one the dynamically-linked DLL uses
# (libstdc++-6.dll's); a std::string built on the DLL side -- heap
# allocated there once its contents outgrow small-string optimization,
# which "Hello, World! (from demo_core)" does -- and then destroyed on
# the executable's side is freed through a DIFFERENT allocator instance
# than the one that allocated it. That is undefined behavior across any
# Windows DLL boundary (well documented -- e.g.
# github.com/msys2/MINGW-packages/issues/5763, a DLL/EXE pair crashing
# the moment an exception -- which unwinds through the same kind of
# per-runtime-instance bookkeeping a heap allocator uses -- crosses a
# static/dynamic runtime mismatch like this one), and on real Windows
# (confirmed directly: some emulators are considerably more lenient
# about a cross-heap free() than real Windows is, so a mismatch like
# this can look fine there and still be live) it reliably crashes
# shortly after the mismatched value is used -- which is exactly what
# this project's own demos did while PMN_MINGW_STATIC_RUNTIME was the
# only option: hello_exe/farewell_exe printed their (still-valid, not
# yet corrupted) greeting and then crashed destroying the very
# std::string they had just printed. Turning this option ON is safe
# again only for a MinGW build with no SHARED module at all, or where
# every SHARED module's boundary is a plain C API (no STL type crosses
# it by value) -- e.g. also statically-linking that module and giving
# it a C entry point avoids the whole class of problem, since it no
# longer depends on the dynamic runtime at all.
# -------------------------------------------------------
option(PMN_MINGW_STATIC_RUNTIME
    "MinGW: statically link libgcc/libstdc++/winpthread into every executable instead of shipping the runtime DLLs next to it. UNSAFE for an executable that also links a MinGW SHARED module (like this project's core_lib) which passes an STL type across that boundary by value -- see the comment above. Default OFF: dynamic linking everywhere, with the runtime DLLs copied automatically."
    OFF)

if(MINGW)
    if(PMN_MINGW_STATIC_RUNTIME)
        add_link_options(
            "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:-static-libgcc;-static-libstdc++;-static;-lwinpthread>"
        )
    endif()

    set(PMN_MINGW_RUNTIME_DLLS "")
    # -print-file-name=<name>.dll only searches "lib"-shaped paths, where
    # the .dll.a import library lives -- not "bin", where the runtime
    # .dll itself does on every package manager here except apt: asked
    # for the bare .dll on those, it just echoes the name back
    # unresolved, silently leaving it out of this list further down.
    # Confirmed directly against each package's own file listing:
    #   pacman  -- /usr/<triplet>/bin/<dll>              (flat)
    #   dnf     -- /usr/<triplet>/sys-root/mingw/bin/<dll> (nested)
    # -- and against discussion.fedoraproject.org's "Location of
    # mingw64/mingw32 system libraries like libgcc_s_seh-1.dll and
    # libwinpthread-1.dll" (Oct 2024) for why dnf's -print-file-name
    # specifically comes up empty. On apt, -print-file-name already
    # resolves the .dll directly (confirmed independently in that same
    # thread) -- both fallbacks below only run where that lookup came
    # back empty, so apt is unaffected either way.
    get_filename_component(_pmn_mingw_cxx_name "${CMAKE_CXX_COMPILER}" NAME)
    string(REGEX REPLACE "-g\\+\\+(\\.exe)?$" "" _pmn_mingw_triplet "${_pmn_mingw_cxx_name}")
    execute_process(
        COMMAND "${CMAKE_CXX_COMPILER}" -print-sysroot
        OUTPUT_VARIABLE _pmn_mingw_sysroot
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    foreach(_pmn_dll_candidate
        libgcc_s_seh-1.dll
        libgcc_s_dw2-1.dll
        libgcc_s_sjlj-1.dll
        libstdc++-6.dll
        libwinpthread-1.dll
    )
        execute_process(
            COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=${_pmn_dll_candidate}
            OUTPUT_VARIABLE _pmn_resolved_dll
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(NOT EXISTS "${_pmn_resolved_dll}")
            if(_pmn_mingw_triplet AND EXISTS "/usr/${_pmn_mingw_triplet}/bin/${_pmn_dll_candidate}")
                set(_pmn_resolved_dll "/usr/${_pmn_mingw_triplet}/bin/${_pmn_dll_candidate}")
            elseif(_pmn_mingw_sysroot AND EXISTS "${_pmn_mingw_sysroot}/mingw/bin/${_pmn_dll_candidate}")
                set(_pmn_resolved_dll "${_pmn_mingw_sysroot}/mingw/bin/${_pmn_dll_candidate}")
            endif()
        endif()
        if(EXISTS "${_pmn_resolved_dll}")
            list(APPEND PMN_MINGW_RUNTIME_DLLS "${_pmn_resolved_dll}")
        endif()
    endforeach()
    if(PMN_MINGW_RUNTIME_DLLS)
        if(PMN_MINGW_STATIC_RUNTIME)
            message(STATUS "MinGW runtime DLLs (bundled next to SHARED targets only -- PMN_MINGW_STATIC_RUNTIME is ON): ${PMN_MINGW_RUNTIME_DLLS}")
        else()
            message(STATUS "MinGW runtime DLLs (bundled next to every EXECUTABLE/SHARED target that needs them): ${PMN_MINGW_RUNTIME_DLLS}")
        endif()
    endif()
endif()

# -------------------------------------------------------
# Build machinery (macros/functions) -- see breeze/cmake/BuildHelpers.cmake.
# This file should change rarely; it holds nothing project-specific.
# -------------------------------------------------------
include("${PMN_BREEZE_CMAKE_DIR}/BuildHelpers.cmake")

# -------------------------------------------------------
# Third-party dependencies -- see breeze/cmake/Dependencies.cmake for
# add_vendor_header_only / add_vendor_subdirectory / add_dependency.
# A module declares its own dependencies in its own CMakeLists.txt (see
# source/Core/CMakeLists.txt for an example); nothing to add here.
# -------------------------------------------------------
include("${PMN_BREEZE_CMAKE_DIR}/Dependencies.cmake")

# -------------------------------------------------------
# Documentation -- see breeze/cmake/Documentation.cmake. Every module
# automatically gets its own Doxygen target the moment Doxygen is
# installed; nothing to add here or in a module's own CMakeLists.txt
# unless you want to opt a module out (NO_DOCS) or override a Doxyfile
# setting (-DDOXYGEN_<TAG>=...).
# -------------------------------------------------------
include("${PMN_BREEZE_CMAKE_DIR}/Documentation.cmake")

# -------------------------------------------------------
# Module discovery
#
# Every module lives in its own directory with its own CMakeLists.txt --
# usually a single add_lib_module/add_objects_module/add_exe_module/
# add_test_module/add_example_module(...) call (see breeze/cmake/BuildHelpers.cmake
# for what each accepts). This file never needs editing to add, remove, or reconfigure
# a module: just add or remove the module's directory + CMakeLists.txt.
#
#   source/<Name>/CMakeLists.txt          -- library, objects or app/executable module
#   source/tests/<Name>/CMakeLists.txt    -- test module
#   source/examples/<Name>/CMakeLists.txt -- example module
#
# (source/tests and source/examples aren't picked up by the first call
# below -- they have no CMakeLists.txt directly inside them, only their
# own children do, so they're only ever visited by their dedicated calls.)
#
# _discover_module_subdirectories() add_subdirectory()s every matching
# directory automatically; CONFIGURE_DEPENDS means the next build
# reconfigures on its own once a module directory is added or removed.
# -------------------------------------------------------
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source")
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source/tests")
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source/examples")

# Object modules (add_objects_module) can only be told from libraries once every
# module exists: this links what each one needs of them -- the pieces behind
# the pieces, and their headers for a library's consumers. See its comment.
_resolve_object_modules()

# Emits <build-dir>/module_manifest-<CONFIG>.txt ("target_name=path_to_binary"
# per line) for every executable module discovered above. breeze/scripts/run.sh / run.bat
# read this to resolve a CMake target name to its binary -- must run after
# discovery.
_write_module_manifest("${CMAKE_BINARY_DIR}")

# Writes out/docs/index.html (DOCS_OUTPUT_DIR, see project/Configuration.cmake)
# linking to every module's generated documentation (a no-op if
# ENABLE_DOXYGEN is off) -- must run after discovery, same reasoning as
# the manifest above.
_write_docs_index("${DOCS_OUTPUT_DIR}")

# -------------------------------------------------------
# Copy compile_commands.json to the project root once it's fully
# populated, so clangd/clang-tidy/IWYU find it without extra config (most
# editors look for it at the repo root or search upward from the source
# file; CMake only ever writes it into the build directory). Runs at
# build time, by which point CMake's own generate step has already
# written build/compile_commands.json, so this works even on the very
# first build with no prior build directory. Vendored and fetched
# dependencies are excluded from it (see breeze/cmake/Dependencies.cmake) so it
# only reflects code this project owns.
# -------------------------------------------------------
if(CMAKE_EXPORT_COMPILE_COMMANDS)
    add_custom_target(copy_compile_commands ALL
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_BINARY_DIR}/compile_commands.json"
            "${COMPILE_COMMANDS_DESTINATION}"
        COMMENT "Copying compile_commands.json to project root"
        VERBATIM
    )
endif()

# -------------------------------------------------------
# install
# -------------------------------------------------------
set(_pmn_install_target_dir ${INSTALL_OUTPUT_DIR}/${DIST_TARGET})

# primary
set(RUNTIME_OUT_DIR  ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR})
set(LIBRARY_OUT_DIR  ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR})
set(ARCHIVE_OUT_DIR  ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR})

# tests -- runtime/library -> bin/tests/   archives -> lib/tests/
set(TEST_RUNTIME_OUT_DIR ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR}/tests)
set(TEST_LIBRARY_OUT_DIR ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR}/tests)
set(TEST_ARCHIVE_OUT_DIR ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR}/tests)

# examples -- runtime/library -> bin/examples/   archives -> lib/examples/
set(EXAMPLE_RUNTIME_OUT_DIR ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR}/examples)
set(EXAMPLE_LIBRARY_OUT_DIR ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR}/examples)
set(EXAMPLE_ARCHIVE_OUT_DIR ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR}/examples)

# Every install(TARGETS ...) below is tagged COMPONENT ${PROJECT_CODE_NAME}.
# A vendored/fetched dependency's own CMakeLists.txt (see
# breeze/cmake/Dependencies.cmake) usually has install() rules of its own, with
# no COMPONENT tag -- installing with `cmake --install build` (no
# --component filter) would pull those in too, typically under
# CMAKE_INSTALL_PREFIX (e.g. /usr/local). breeze/scripts/install.sh / install.bat always
# pass --component ${PROJECT_CODE_NAME} so only this project's own
# artifacts are installed; use the same flag if you invoke cmake --install
# directly.
message(STATUS "Will install primary modules.")
get_property(_pmn_primary_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_PRIMARY)
if(_pmn_primary_targets)
    install(TARGETS ${_pmn_primary_targets}
        COMPONENT ${PROJECT_CODE_NAME}
        ARCHIVE DESTINATION ${ARCHIVE_OUT_DIR}
        LIBRARY DESTINATION ${LIBRARY_OUT_DIR}
        RUNTIME DESTINATION ${RUNTIME_OUT_DIR}
    )
endif()

# MinGW runtime DLLs (see the "MinGW runtime linking" comment above) --
# installed as plain files, alongside the DLLs above, rather than as
# TARGETS, since they're not CMake targets this project defines. RUNTIME,
# not LIBRARY: a .dll is a runtime artifact on Windows no matter which
# install()-TARGETS category built it. Always into RUNTIME_OUT_DIR: the
# primary executables land there, and so does core_lib/demo_core.dll,
# which needs this regardless of PMN_MINGW_STATIC_RUNTIME (see that
# option's comment -- a SHARED module is never a candidate for it).
if(PMN_MINGW_RUNTIME_DLLS)
    install(FILES ${PMN_MINGW_RUNTIME_DLLS}
        COMPONENT ${PROJECT_CODE_NAME}
        DESTINATION ${RUNTIME_OUT_DIR}
    )
endif()

# Both blocks below read whatever test/example modules discovery actually
# found -- no target names to keep in sync here when a module is added,
# removed, or renamed.
if(INSTALL_TESTS)
    get_property(_pmn_test_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_TEST)
    if(_pmn_test_targets)
        message(STATUS "Will install test modules: ${_pmn_test_targets}")
        install(TARGETS ${_pmn_test_targets}
            COMPONENT ${PROJECT_CODE_NAME}
            ARCHIVE DESTINATION ${TEST_ARCHIVE_OUT_DIR}
            LIBRARY DESTINATION ${TEST_LIBRARY_OUT_DIR}
            RUNTIME DESTINATION ${TEST_RUNTIME_OUT_DIR}
        )
        # Matches BuildHelpers.cmake's add_test_module: skipped under
        # PMN_MINGW_STATIC_RUNTIME, where test executables are
        # self-contained instead.
        if(PMN_MINGW_RUNTIME_DLLS AND NOT PMN_MINGW_STATIC_RUNTIME)
            install(FILES ${PMN_MINGW_RUNTIME_DLLS}
                COMPONENT ${PROJECT_CODE_NAME}
                DESTINATION ${TEST_RUNTIME_OUT_DIR}
            )
        endif()
        # The install-time match for _copy_target_runtime_dlls(): a test
        # that depends on a SHARED module (core_lib included) needs that
        # module's .dll installed alongside it too, on any Windows
        # compiler -- bin/tests/ is a separate install destination from
        # bin/, and Windows has no relative-RPATH equivalent (see that
        # function's comment). install(FILES) silently installs nothing
        # for a target with no SHARED dependency -- confirmed directly --
        # so this needs no separate "is there anything to install" guard.
        if(WIN32)
            foreach(_pmn_test_target ${_pmn_test_targets})
                install(FILES "$<TARGET_RUNTIME_DLLS:${_pmn_test_target}>"
                    COMPONENT ${PROJECT_CODE_NAME}
                    DESTINATION ${TEST_RUNTIME_OUT_DIR}
                )
            endforeach()
        endif()
    else()
        message(WARNING "INSTALL_TESTS is ON but no test modules were found under source/tests/.")
    endif()
endif()

if(INSTALL_EXAMPLES)
    get_property(_pmn_example_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_EXAMPLE)
    if(_pmn_example_targets)
        message(STATUS "Will install example modules: ${_pmn_example_targets}")
        install(TARGETS ${_pmn_example_targets}
            COMPONENT ${PROJECT_CODE_NAME}
            ARCHIVE DESTINATION ${EXAMPLE_ARCHIVE_OUT_DIR}
            LIBRARY DESTINATION ${EXAMPLE_LIBRARY_OUT_DIR}
            RUNTIME DESTINATION ${EXAMPLE_RUNTIME_OUT_DIR}
        )
        # See the matching pair of comments in the INSTALL_TESTS block above.
        if(PMN_MINGW_RUNTIME_DLLS AND NOT PMN_MINGW_STATIC_RUNTIME)
            install(FILES ${PMN_MINGW_RUNTIME_DLLS}
                COMPONENT ${PROJECT_CODE_NAME}
                DESTINATION ${EXAMPLE_RUNTIME_OUT_DIR}
            )
        endif()
        if(WIN32)
            foreach(_pmn_example_target ${_pmn_example_targets})
                install(FILES "$<TARGET_RUNTIME_DLLS:${_pmn_example_target}>"
                    COMPONENT ${PROJECT_CODE_NAME}
                    DESTINATION ${EXAMPLE_RUNTIME_OUT_DIR}
                )
            endforeach()
        endif()
    else()
        message(WARNING "INSTALL_EXAMPLES is ON but no example modules were found under source/examples/.")
    endif()
endif()
