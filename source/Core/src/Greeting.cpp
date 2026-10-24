#include "core/Greeting.hpp"

#include <fmt/format.h>

namespace demo::core
{

	std::string makeGreeting(const std::string& name)
	{
		return fmt::format("Hello, {}! (from {})", name, MODULE_NAME);
	}

}
