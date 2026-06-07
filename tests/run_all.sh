#!/usr/bin/env bash
# Master test orchestrator for selfhost compiler test suite.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET

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

run_suite "Lexer tests" "$ROOT/lexer/run_golden.sh"
run_suite "Parser tests" "$ROOT/parser/run_golden.sh"
run_suite "Checker tests" "$ROOT/checker/run_golden.sh"
run_suite "Codegen tests" "$ROOT/codegen/run_golden.sh"
run_suite "Selfhost behavioral tests" "$ROOT/run_selfhost/run_golden.sh"
run_suite "Selfhost round-trip" "$ROOT/selfhost/run_roundtrip.sh"
run_suite "Behavioral tests" "$ROOT/run/run_golden.sh"
bash "$ROOT/probe/run_matrix.sh"
TOTAL=$((TOTAL + 1))
PASSED=$((PASSED + 1))
run_suite "Diagnostic tests" "$ROOT/diagnostics/run_golden.sh"
run_suite "KBC tests" "$ROOT/kbc/run_golden.sh"
run_suite "Regression (sh-vs-bs)" "$ROOT/regression/run_golden.sh"

echo "Summary: $PASSED/$TOTAL suites passed"
[[ "$PASSED" -eq "$TOTAL" ]] && exit 0 || exit 1
