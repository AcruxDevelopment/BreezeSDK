#include "tiny_case.h"

#include <algorithm>
#include <cctype>

std::string tiny_case_to_upper(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                    [](unsigned char c) { return std::toupper(c); });
    return s;
}
