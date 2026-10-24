# =============================================================================
# CopyRuntimeDlls.cmake
#
# Usage (from a POST_BUILD add_custom_command; see BuildHelpers.cmake's
# _copy_target_runtime_dlls()):
#   cmake -DDEST=<dir> "-DFILES=$<TARGET_RUNTIME_DLLS:tgt>" -P CopyRuntimeDlls.cmake
#
# Exists only because `cmake -E copy_if_different <dest>` -- the obvious,
# one-line way to do this -- errors out (and fails the whole build) when
# given zero source files, which $<TARGET_RUNTIME_DLLS:tgt> legitimately
# evaluates to for most targets (anything that links no SHARED library,
# which is most executables in most projects, this one's included: only
# a target that depends on a SHARED module -- like core_lib -- has any
# files here at all). Confirmed directly: without this indirection, that
# empty case stops the build with cmake -E's own usage text as the error.
# A plain `if(FILES)` here is all it takes to make "nothing to do" a
# success instead of a build failure.
# =============================================================================
if(FILES)
    file(COPY ${FILES} DESTINATION "${DEST}")
endif()
