# An objects module: compiled to object files and nothing else -- no library of
# its own. source/Core names it in its DEPENDS, so the objects end up inside
# demo_core, and because that is a library, the header below is visible to
# everything that uses core_lib. OUTPUT_NAME is only the name MODULE_NAME
# carries: the farewell still says "(from demo_core)". fmt::fmt is declared in
# source/Core/CMakeLists.txt.
add_objects_module(core_farewell OUTPUT_NAME "demo_core" DEPENDS fmt::fmt)
