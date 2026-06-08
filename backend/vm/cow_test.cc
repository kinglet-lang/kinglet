#include "vm/cow.h"
#include "vm/value.h"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool cond, const char *msg) {
  if (!cond) {
    std::cerr << "FAIL: " << msg << '\n';
    std::exit(1);
  }
}

void test_shared_assign_clones() {
  kinglet::Value a = kinglet::Value::array_value(
      {kinglet::Value::int_value(1), kinglet::Value::int_value(2)});
  kinglet::Value b = a;
  expect(a.heap.ptr == b.heap.ptr, "copy should share heap");
  expect(a.heap.ptr->refcount == 2, "shared refcount");

  kinglet::Value assigned = kinglet::value_deep_clone(a);
  expect(a.heap.ptr != assigned.heap.ptr, "assign clone should fork");
}

void test_cross_local_assign_clones() {
  kinglet::Value a = kinglet::Value::array_value(
      {kinglet::Value::int_value(1)});
  kinglet::Value b = a;
  kinglet::Value assigned = kinglet::value_deep_clone(a);
  expect(assigned.heap.ptr != a.heap.ptr, "cross-local assign clones");
}

void test_cow_on_shared_mutation() {
  kinglet::Value a = kinglet::Value::array_value(
      {kinglet::Value::int_value(1)});
  kinglet::Value b = a;
  kinglet::cow_ensure_unique(b);
  expect(a.heap.ptr != b.heap.ptr, "mutation COW forks");
  static_cast<kinglet::HeapArray *>(b.heap.ptr)
      ->elements.push_back(kinglet::Value::int_value(2));
  expect(static_cast<kinglet::HeapArray *>(a.heap.ptr)->elements.size() == 1,
         "original unchanged after COW mutate");
}

void test_sole_owner_no_cow() {
  kinglet::Value a = kinglet::Value::array_value(
      {kinglet::Value::int_value(1)});
  void *before = a.heap.ptr;
  kinglet::cow_ensure_unique(a);
  expect(a.heap.ptr == before, "sole owner should not COW");
}

} // namespace

int main() {
  test_shared_assign_clones();
  test_cross_local_assign_clones();
  test_cow_on_shared_mutation();
  test_sole_owner_no_cow();
  std::cout << "cow_test: ok\n";
  return 0;
}
