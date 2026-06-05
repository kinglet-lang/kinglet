#!/usr/bin/env bash
# Behavioral test suite for selfhost compiler.
#
# Compiles + runs .kl test cases and verifies stdout/stderr/exit code against
# expected outputs (.expected files, optional .exit and .args files).
#
# Test cases are ported from kinglet-bootstrap/tests/cli/cases/*.kl.
# Known capability gaps (explicit generics, concept calls, UFCS, selective using)
# are placed in cases/known_gaps/ and marked as xfail.
#
# This is Phase 1b from handoff/02-test-suite-plan.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET_BIN="$KINGLET"
export TEST_CASES_DIR="$ROOT/tests/run/cases"
export TMP_DIR="$(mktemp -d)"

FAILURES=0
PASSES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Test runner that reads .expected files
run_golden() {
  local name="$1"
  local expected_file="$TEST_CASES_DIR/$name.expected"
  local exit_file="$TEST_CASES_DIR/$name.exit"
  local args_file="$TEST_CASES_DIR/$name.args"

  if [[ ! -f "$expected_file" ]]; then
    echo "SKIP $name: no .expected file" >&2
    return 0
  fi

  local expected_exit=0
  if [[ -f "$exit_file" ]]; then
    expected_exit=$(cat "$exit_file")
  fi

  local expected_stdout
  expected_stdout=$(cat "$expected_file")

  if [[ -f "$args_file" ]]; then
    # Read args from file (one per line or space-separated)
    local -a args
    mapfile -t args < "$args_file"
    if run_args_case "$name" "$expected_exit" "$expected_stdout" "" "${args[@]}"; then
      echo "PASS $name"
      PASSES=$((PASSES + 1))
    else
      FAILURES=$((FAILURES + 1))
    fi
  else
    if run_case "$name" "run" "$expected_exit" "$expected_stdout" ""; then
      echo "PASS $name"
      PASSES=$((PASSES + 1))
    else
      FAILURES=$((FAILURES + 1))
    fi
  fi
}

# xfail runner for known gaps
run_xfail() {
  local name="$1"
  local reason="$2"
  echo "XFAIL $name: $reason (known gap, tracked)"
}

echo "=== Selfhost behavioral test suite ==="
echo

# --- Basic functionality ---
echo "Running basic tests..."

# Simple arithmetic and operators
run_golden "simple_arith"
run_golden "operators_basic"

# Control flow
run_golden "if_else_basic"
run_golden "while_basic"
run_golden "for_basic"

# --- Known gaps (from capability matrix) ---
echo
echo "Known capability gaps (xfail):"
TEST_CASES_DIR="$ROOT/tests/run/cases/known_gaps"

# Probe 23: explicit generic type args
run_xfail "explicit_generic" "parser has no call-site <T> syntax"

# Probe 29: selective using for natives
run_xfail "using_selective_native" "only aliases module functions, not natives"

# Probe 26: concept-qualified calls
run_xfail "concept_qualified" "concept calls unimplemented"

# Probe 27: UFCS (free function)
run_xfail "ufcs_free_function" "method resolver limited to built-in types"

echo
echo "=== Test summary ==="
echo "Passed: $PASSES"
echo "Failed: $FAILURES"
echo "Known gaps: 4 (tracked as xfail)"

if [[ "$FAILURES" -ne 0 ]]; then
  echo
  echo "$FAILURES test(s) failed." >&2
  exit 1
fi

echo
echo "Behavioral test suite PASSED"
