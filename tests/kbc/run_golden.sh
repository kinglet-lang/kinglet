#!/usr/bin/env bash
# KBC serialize/deserialize round-trip test suite.
#
# Tests that compiled .kbc bytecode:
# 1. Deserializes correctly and produces expected output
# 2. Full vs --strip-debug builds are behaviorally equivalent
# 3. Corrupted .kbc files fail gracefully
#
# This exercises compiler/bytecode.kl (serialization) ↔ backend/vm
# (deserialization) faithfulness.
#
# Implements Phase 2c from handoff/02-test-suite-plan.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET_BIN="$KINGLET"
export TEST_CASES_DIR="$ROOT/tests/kbc/cases"
export TMP_DIR="$(mktemp -d)"

FAILURES=0
PASSES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Test KBC round-trip: compile, run, verify output
test_kbc_roundtrip() {
  local name="$1"
  local expected_output="$2"

  local source="$TEST_CASES_DIR/$name.kl"
  local kbc="$TMP_DIR/$name.kbc"
  local stdout="$TMP_DIR/$name.stdout"
  local stderr="$TMP_DIR/$name.stderr"

  if [[ ! -f "$source" ]]; then
    echo "SKIP $name: no .kl file" >&2
    return 0
  fi

  # Compile to .kbc
  if ! compile_kl "$source" "$kbc" 2>"$stderr"; then
    echo "FAIL $name: compilation failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # Run .kbc
  if ! run_kbc "$kbc" >"$stdout" 2>"$stderr"; then
    echo "FAIL $name: runtime failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  strip_cr "$stdout"

  # Verify output
  if [[ "$(cat "$stdout")" != "$expected_output" ]]; then
    echo "FAIL $name: output mismatch" >&2
    echo "  Expected: $expected_output" >&2
    echo "  Got: $(cat "$stdout")" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  echo "PASS $name (round-trip)"
  PASSES=$((PASSES + 1))
}

# Test that --strip-debug produces same behavior
test_strip_debug() {
  local name="$1"
  local expected_output="$2"

  local source="$TEST_CASES_DIR/$name.kl"
  local kbc_full="$TMP_DIR/$name.full.kbc"
  local kbc_stripped="$TMP_DIR/$name.stripped.kbc"
  local stdout_full="$TMP_DIR/$name.full.stdout"
  local stdout_stripped="$TMP_DIR/$name.stripped.stdout"

  # Compile both versions
  compile_kl "$source" "$kbc_full" 2>/dev/null || return 1
  compile_kl "$source" "$kbc_stripped" --strip-debug 2>/dev/null || return 1

  # Run both
  run_kbc "$kbc_full" >"$stdout_full" 2>/dev/null || return 1
  run_kbc "$kbc_stripped" >"$stdout_stripped" 2>/dev/null || return 1

  strip_cr "$stdout_full" "$stdout_stripped"

  # Should have identical output
  if ! diff -q "$stdout_full" "$stdout_stripped" >/dev/null; then
    echo "FAIL $name: --strip-debug changed behavior" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # Stripped should be smaller (or equal if no debug info)
  local size_full=$(stat -c%s "$kbc_full" 2>/dev/null || stat -f%z "$kbc_full")
  local size_stripped=$(stat -c%s "$kbc_stripped" 2>/dev/null || stat -f%z "$kbc_stripped")

  if [[ "$size_stripped" -gt "$size_full" ]]; then
    echo "FAIL $name: stripped larger than full" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  echo "PASS $name (strip-debug: $size_full → $size_stripped bytes)"
  PASSES=$((PASSES + 1))
}

# Test that corrupted .kbc fails gracefully
test_corrupted_kbc() {
  local kbc="$TMP_DIR/corrupted.kbc"
  local stderr="$TMP_DIR/corrupted.stderr"

  # Create corrupted .kbc (truncated)
  echo "TRUNCATED" > "$kbc"

  # Should fail with error message (not crash)
  if run_kbc "$kbc" >/dev/null 2>"$stderr"; then
    echo "FAIL corrupted_kbc: should have failed" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # Should have error message
  if [[ ! -s "$stderr" ]]; then
    echo "FAIL corrupted_kbc: no error message" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  echo "PASS corrupted_kbc (graceful failure)"
  PASSES=$((PASSES + 1))
}

echo "=== KBC serialize/deserialize test suite ==="
echo

# --- Round-trip tests ---
echo "Round-trip tests:"
test_kbc_roundtrip "simple_return" "42"
test_kbc_roundtrip "hello_world" $'hello world\n'
test_kbc_roundtrip "arithmetic" "15"

# --- Strip-debug tests ---
echo
echo "Strip-debug tests:"
test_strip_debug "simple_return" "42"
test_strip_debug "hello_world" $'hello world\n'

# --- Corrupted .kbc test ---
echo
echo "Corrupted .kbc test:"
test_corrupted_kbc

echo
echo "=== KBC test summary ==="
echo "Passed: $PASSES"
echo "Failed: $FAILURES"

if [[ "$FAILURES" -ne 0 ]]; then
  echo
  echo "$FAILURES KBC test(s) failed." >&2
  exit 1
fi

echo
echo "KBC test suite PASSED"
