# A stand-in for a "real" vendored third-party library that ships its own
# build -- a plain source drop, git submodule, or git subtree checked into
# vendor/tiny_case/. Added via add_vendor_subdirectory(tiny_case) in the
# root CMakeLists.txt, not discovered by the module system (vendor/ isn't
# one of the discovery roots), and not written to conform to this
# project's conventions -- it's whatever the upstream project's
# CMakeLists.txt looks like.
cmake_minimum_required(VERSION 3.16)
add_library(tiny_case STATIC src/tiny_case.cpp)
target_include_directories(tiny_case PUBLIC include)
