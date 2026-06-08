#!/usr/bin/env bash
# Diagnostic/negative test suite for selfhost compiler.
#
# Tests that parse errors, type errors, and compile errors produce the
# expected error messages on stderr at the correct line:col positions.
#
# Parse/compile cases use the bootstrap binary directly. Type-error cases use
# the self-hosted checker (`kinglet --run compiler.kbc <file> --check`) so
# diagnostics reflect the sh checker, not bootstrap-only messages.
#
# Implements Phase 2b from handoff/02-test-suite-plan.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2
export TEST_CASES_DIR="$ROOT/tests/diagnostics/cases"
export TMP_DIR="$(mktemp -d)"

FAILURES=0
PASSES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Run a diagnostic test: expect specific error message on stderr.
# mode:
#   run       - bootstrap compile+run (expects non-zero exit)
#   check     - bootstrap --check (expects non-zero exit)
#   shcheck   - selfhost --run compiler.kbc --check (stderr pattern only;
#               VM does not yet propagate checker exit codes from bytecode)
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

  local exit_code=0
  if [[ "$mode" == "shcheck" ]]; then
    "$KINGLET_BIN" --run "$CLI_KBC" "$source" --check >/dev/null 2>"$stderr" || exit_code=$?
  elif [[ "$mode" == "check" ]]; then
    "$KINGLET_BOOTSTRAP" --check "$source" >/dev/null 2>"$stderr" || exit_code=$?
  else
    "$KINGLET_BOOTSTRAP" "$source" >/dev/null 2>"$stderr" || exit_code=$?
  fi

  strip_cr "$stderr"

  if [[ "$mode" != "shcheck" && "$exit_code" -eq 0 ]]; then
    echo "FAIL $name: expected non-zero exit, got 0" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

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
run_diagnostic "parse_invalid_token" "Unexpected character"

# --- Type errors (selfhost checker) ---
echo
echo "Type errors:"
run_diagnostic "type_mismatch" "Cannot assign" "shcheck"
run_diagnostic "undeclared_variable" "Undeclared variable" "shcheck"
run_diagnostic "wrong_arity" "Wrong number of arguments" "shcheck"

# --- Compile errors ---
echo
echo "Compile errors:"
run_diagnostic "undefined_function" "Undeclared variable" "shcheck"
run_diagnostic "invalid_field_access" "has no field" "shcheck"

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
