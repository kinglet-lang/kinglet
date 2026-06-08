#include "vm/cow.h"

#include "vm/value.h"

#include <vector>

namespace kinglet {

namespace {

std::vector<Value> clone_fields(const std::vector<Value> &fields) {
  std::vector<Value> out;
  out.reserve(fields.size());
  for (const Value &field : fields) {
    out.push_back(value_deep_clone(field));
  }
  return out;
}

} // namespace

Value value_deep_clone(const Value &value) {
  if (!value.heap) {
    return value;
  }

  switch (value.type) {
  case ValueType::String: {
    auto *old = static_cast<const HeapString *>(value.heap.ptr);
    return Value::string_value(old->value);
  }
  case ValueType::Struct: {
    auto *old = static_cast<const HeapStruct *>(value.heap.ptr);
    return Value::struct_value(old->type_index, clone_fields(old->fields));
  }
  case ValueType::Array: {
    auto *old = static_cast<const HeapArray *>(value.heap.ptr);
    return Value::array_value(clone_fields(old->elements));
  }
  case ValueType::Map: {
    auto *old = static_cast<const HeapMap *>(value.heap.ptr);
    Value copy = Value::map_value();
    auto *m = static_cast<HeapMap *>(copy.heap.ptr);
    m->order = old->order;
    for (const std::string &ek : old->order) {
      const MapEntry &entry = old->entries.at(ek);
      m->entries[ek] = MapEntry{value_deep_clone(entry.key),
                                value_deep_clone(entry.value)};
    }
    return copy;
  }
  case ValueType::Enum: {
    auto *old = static_cast<const HeapEnum *>(value.heap.ptr);
    return Value::enum_value_with_payload(old->type_index, old->variant_index,
                                          clone_fields(old->payload));
  }
  default:
    return value;
  }
}

void cow_ensure_unique(Value &value) {
  if (!value.heap || value.heap.ptr->refcount <= 1)
    return;

  switch (value.type) {
  case ValueType::String: {
    auto *old = static_cast<HeapString *>(value.heap.ptr);
    value.heap = RcPtr<HeapObj>{new HeapString(old->value)};
    break;
  }
  case ValueType::Struct: {
    auto *old = static_cast<HeapStruct *>(value.heap.ptr);
    value.heap =
        RcPtr<HeapObj>{new HeapStruct(old->type_index, old->fields)};
    break;
  }
  case ValueType::Array: {
    auto *old = static_cast<HeapArray *>(value.heap.ptr);
    value.heap = RcPtr<HeapObj>{new HeapArray(old->elements)};
    break;
  }
  case ValueType::Map: {
    auto *old = static_cast<HeapMap *>(value.heap.ptr);
    auto *copy = new HeapMap();
    copy->order = old->order;
    copy->entries = old->entries;
    value.heap = RcPtr<HeapObj>{copy};
    break;
  }
  case ValueType::Enum: {
    auto *old = static_cast<HeapEnum *>(value.heap.ptr);
    value.heap = RcPtr<HeapObj>{new HeapEnum(old->type_index,
                                              old->variant_index,
                                              old->payload)};
    break;
  }
  default:
    break;
  }
}

} // namespace kinglet
