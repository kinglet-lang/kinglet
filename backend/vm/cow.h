#pragma once

namespace kinglet {

struct Value;

// Deep copy for cross-variable assignment when the heap object is shared.
Value value_deep_clone(const Value &value);

// Clone before in-place mutation when refcount > 1.
void cow_ensure_unique(Value &value);

} // namespace kinglet
