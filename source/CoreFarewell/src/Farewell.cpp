#include "core/Farewell.hpp"

#include <fmt/format.h>

namespace demo::core
{

	std::string makeFarewell(const std::string& name)
	{
		return fmt::format("Farewell, {}. (from {})", name, MODULE_NAME);
	}

}
