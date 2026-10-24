# fmt: fetched from source at the pinned tag, unless an installed copy that
# is at least version 12 is found first.
#
#   GIT_TAG 12.1.0             the version this template is built and tested
#                              with. Anything older than 11.1 does not compile
#                              with Clang >= 21 (including clang-cl): its
#                              FMT_STRING macro, used inside fmt's own sources,
#                              is rejected as "not a constant expression"
#                              (fmtlib/fmt#4807). 12.x also drops the
#                              fmt::format-via-<fmt/core.h> shim, which is why
#                              Greeting.cpp includes <fmt/format.h>.
#                              Deliberately not the newest release, 12.2.0:
#                              that one doesn't compile for 32-bit x86
#                              (windows-x86-mingw32) -- its fallback for a
#                              missing __int128 lacks operator~ -- and the
#                              fix, fmtlib/fmt#4813, landed on main after the
#                              tag. Move up once a release contains it.
#   FIND_PACKAGE_ARGS 12 ...   the "12" is a minimum version for an installed
#                              copy. Without it ANY installed fmt beats the
#                              pin -- distro packages are old (Ubuntu 24.04
#                              ships 9.1, 26.04 ships 10.1) and would quietly
#                              bring the Clang >= 21 failure back.
#   GIT_SHALLOW TRUE           every preset has its own build directory (and
#                              so its own _deps/), so keep each fetch small.
#
#   FMT_MODULE OFF             fmt 12 turns its C++20 named-module library on
#                              BY DEFAULT whenever CMake >= 3.28, C++20, Ninja
#                              >= 1.11 and Clang >= 16 / GCC >= 15 / MSVC >= 19.34 are all
#                              in play -- which this project's setup is, on
#                              most machines. That adds a module-interface
#                              build nothing here uses, and needs module
#                              dependency scanning (clang-scan-deps for
#                              Clang, which e.g. Ubuntu's plain `clang`
#                              package doesn't include). Cached without FORCE
#                              so an explicit -DFMT_MODULE=ON still wins.
set(FMT_MODULE OFF CACHE BOOL
    "Build fmt's C++20 named-module library (not used by this project)")

add_dependency(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        12.1.0
    GIT_SHALLOW    TRUE
    FIND_PACKAGE_ARGS 12 NAMES fmt
)

# core_farewell is an objects module (source/CoreFarewell): a piece of this
# library with a module of its own. Naming it here is all it takes for its
# object files to go into demo_core and its header to reach core_lib's users.
add_lib_module(core_lib TYPE SHARED OUTPUT_NAME "demo_core" DEPENDS fmt::fmt core_farewell)
