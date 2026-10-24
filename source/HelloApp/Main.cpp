#include <iostream>
#include <string>

#include "core/Greeting.hpp"
#include "tiny_ansi.h"

// Executable module "hello_exe" (see HelloApp/CMakeLists.txt).
// Run it via:  scripts/run.sh hello_exe [name]
int main(int argc, char** argv)
{
	const std::string name = (argc > 1) ? argv[1] : "World";
	std::cout << tiny_ansi::green(demo::core::makeGreeting(name)) << std::endl;
	return 0;
}
