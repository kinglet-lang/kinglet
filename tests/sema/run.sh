#!/usr/bin/env bash
# Semantic (type checker) tests via harness (decision 0012 phase 3).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/tests/harness/run.sh" \
  "$ROOT/tests/sema/pass" \
  "$ROOT/tests/sema/fail" \
  "$ROOT/tests/sema/warn"
