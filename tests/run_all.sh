#!/usr/bin/env bash
# Master test orchestrator for selfhost compiler test suite.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2

echo "========================================"
echo "Kinglet Selfhost Test Suite"
echo "========================================"

TOTAL=0
PASSED=0

run_suite() {
  TOTAL=$((TOTAL + 1))
  echo "Running: $1"
  if bash "$2"; then
    echo "✓ $1 PASSED"
    PASSED=$((PASSED + 1))
  else
    echo "✗ $1 FAILED"
  fi
  echo
}

run_suite "Lexer tests" "$ROOT/tests/lexer/run_golden.sh"
run_suite "Parser tests" "$ROOT/tests/parser/run_golden.sh"
run_suite "Sema tests (pass + fail)" "$ROOT/tests/sema/run.sh"
run_suite "Codegen tests" "$ROOT/tests/codegen/run_golden.sh"
run_suite "Selfhost behavioral tests" "$ROOT/tests/run_selfhost/run_golden.sh"
run_suite "Selfhost round-trip" "$ROOT/tests/selfhost/run_roundtrip.sh"
run_suite "Exec tests (selfhost)" "$ROOT/tests/exec/run.sh"
run_suite "Differential (bootstrap vs selfhost)" "$ROOT/tests/differential/run.sh"
bash "$ROOT/tests/probe/run_matrix.sh"
TOTAL=$((TOTAL + 1))
PASSED=$((PASSED + 1))
bash "$ROOT/tests/builtin_methods/run_matrix.sh"
TOTAL=$((TOTAL + 1))
PASSED=$((PASSED + 1))
run_suite "Diagnostic tests" "$ROOT/tests/diagnostics/run_golden.sh"
run_suite "KBC tests" "$ROOT/tests/kbc/run_golden.sh"
run_suite "Regression (oracle + drift)" "$ROOT/tests/regression/run_golden.sh"
bash "$ROOT/tests/differential/run_matrix.sh"
TOTAL=$((TOTAL + 1))
PASSED=$((PASSED + 1))
run_suite "Property (round-trip + fuzz)" "$ROOT/tests/property/run.sh"

echo "Summary: $PASSED/$TOTAL suites passed"
[[ "$PASSED" -eq "$TOTAL" ]] && exit 0 || exit 1
