#include <iostream>
#include <string>

#include "core/Farewell.hpp"
#include "tiny_case.h"

// Executable module "farewell_exe" (see FarewellApp/CMakeLists.txt).
// Run it via:  scripts/run.sh farewell_exe [name]
int main(int argc, char** argv)
{
	const std::string name = (argc > 1) ? argv[1] : "World";
	std::cout << demo::core::makeFarewell(tiny_case_to_upper(name)) << std::endl;
	return 0;
}
