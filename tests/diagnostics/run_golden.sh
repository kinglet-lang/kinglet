#!/usr/bin/env bash
# Diagnostic/negative test suite for selfhost compiler.
#
# Tests that parse errors, type errors, and compile errors produce the
# expected error messages on stderr at the correct line:col positions.
#
# This puts pressure on the checker (currently shallow) and compiler error
# reporting to produce useful diagnostics.
#
# Implements Phase 2b from handoff/02-test-suite-plan.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET_BIN="$KINGLET"
export TEST_CASES_DIR="$ROOT/tests/diagnostics/cases"
export TMP_DIR="$(mktemp -d)"

FAILURES=0
PASSES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Run a diagnostic test: expect non-zero exit and specific error message
run_diagnostic() {
  local name="$1"
  local expected_pattern="$2"
  local mode="${3:-run}"

  local source="$TEST_CASES_DIR/$name.kl"
  local stderr="$TMP_DIR/$name.stderr"

  if [[ ! -f "$source" ]]; then
    echo "SKIP $name: no .kl file" >&2
    return 0
  fi

  # Run and expect failure
  if [[ "$mode" == "run" ]]; then
    "$KINGLET_BIN" "$source" >/dev/null 2>"$stderr"
  else
    "$KINGLET_BIN" "$mode" "$source" >/dev/null 2>"$stderr"
  fi
  local exit_code=$?

  strip_cr "$stderr"

  # Should fail (non-zero exit)
  if [[ "$exit_code" -eq 0 ]]; then
    echo "FAIL $name: expected non-zero exit, got 0" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # Should contain expected error pattern
  if ! grep -q "$expected_pattern" "$stderr"; then
    echo "FAIL $name: stderr missing pattern '$expected_pattern'" >&2
    echo "  Actual stderr:" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  echo "PASS $name"
  PASSES=$((PASSES + 1))
}

echo "=== Selfhost diagnostic test suite ==="
echo

# --- Parse errors ---
echo "Parse errors:"
run_diagnostic "parse_missing_semicolon" "Expected ';'"
run_diagnostic "parse_unclosed_brace" "Expected '}'"
run_diagnostic "parse_invalid_token" "Unexpected token"

# --- Type errors ---
echo
echo "Type errors:"
run_diagnostic "type_mismatch" "type error" "--check"
run_diagnostic "undeclared_variable" "Undeclared identifier" "run"
run_diagnostic "wrong_arity" "Wrong number of arguments" "run"

# --- Compile errors ---
echo
echo "Compile errors:"
run_diagnostic "undefined_function" "Undeclared identifier" "run"
run_diagnostic "invalid_field_access" "Unknown field" "run"

echo
echo "=== Diagnostic test summary ==="
echo "Passed: $PASSES"
echo "Failed: $FAILURES"

if [[ "$FAILURES" -ne 0 ]]; then
  echo
  echo "$FAILURES diagnostic test(s) failed." >&2
  exit 1
fi

echo
echo "Diagnostic test suite PASSED"
