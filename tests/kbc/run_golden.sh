#!/usr/bin/env bash
# KBC serialize/deserialize round-trip test suite.
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

test_kbc_roundtrip() {
  local name="$1"
  local expected_output="$2"
  local source="$TEST_CASES_DIR/$name.kl"
  local kbc="$TMP_DIR/$name.kbc"
  local stdout="$TMP_DIR/$name.stdout"
  
  if [[ ! -f "$source" ]]; then
    echo "SKIP $name: no .kl file" >&2
    return 0
  fi
  
  compile_kl "$source" "$kbc" 2>/dev/null || { FAILURES=$((FAILURES + 1)); return 1; }
  run_kbc "$kbc" >"$stdout" 2>/dev/null || { FAILURES=$((FAILURES + 1)); return 1; }
  strip_cr "$stdout"
  
  if [[ "$(cat "$stdout")" != "$expected_output" ]]; then
    echo "FAIL $name: output mismatch" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
  
  echo "PASS $name"
  PASSES=$((PASSES + 1))
}

echo "=== KBC test suite ==="
test_kbc_roundtrip "simple_return" "42"
test_kbc_roundtrip "hello_world" $'hello world\n'
test_kbc_roundtrip "arithmetic" "15"

echo
echo "Passed: $PASSES, Failed: $FAILURES"
[[ "$FAILURES" -eq 0 ]] && echo "KBC tests PASSED" || exit 1
