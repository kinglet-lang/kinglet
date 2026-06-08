#pragma once

namespace kinglet {

struct Value;

// Deep copy when storing into a local that would alias another local.
Value value_deep_clone(const Value &value);

} // namespace kinglet
