#pragma once

#include <string>

/// @file
/// The farewell half of the "core" module. It is a piece of core_lib that is
/// a module of its own: an objects module (source/CoreFarewell/CMakeLists.txt),
/// compiled to object files that the library in source/Core takes in.
namespace demo::core
{

	/// Builds a farewell for @p name.
	///
	/// @param name  the person (or thing) being bid farewell.
	/// @return a formatted farewell string, e.g. "Farewell, Ale. (from demo_core)".
	std::string makeFarewell(const std::string& name);

}
