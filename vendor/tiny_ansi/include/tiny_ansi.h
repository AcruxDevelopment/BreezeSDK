#pragma once
// Vendored header-only helper (vendor/tiny_ansi/) -- a stand-in for the
// kind of tiny, buildless third-party header you'd wrap with
// add_vendor_header_only() instead of writing yourself.
#include <string>

namespace tiny_ansi {

inline std::string green(const std::string& s) {
    return "\033[32m" + s + "\033[0m";
}

}  // namespace tiny_ansi
