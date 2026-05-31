#!/usr/bin/env bash
# Checker golden tests for the self-hosted Kinglet checker.
# Runs `kinglet --run cli.kbc --check <case>.kl` and verifies expected
# pass/fail. Uses the cached cli.kbc artefact so each case takes ~70ms
# instead of recompiling cli/main.kl from source.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET") || exit 2

CASES="$ROOT/tests/checker/cases"

PASS=0
FAIL=0
TOTAL=0

run_case() {
  local name="$1"
  local expect_pass="$2"
  local file="$CASES/$name.kl"
  TOTAL=$((TOTAL + 1))

  # Strip warnings for cleaner output
  local output
  output=$("$KINGLET" --run "$CLI_KBC" --check "$file" 2>&1 | grep -v warning || true)

  if [ "$expect_pass" = "pass" ]; then
    if echo "$output" | grep -q "OK: no type errors"; then
      echo "  PASS  $name"
      PASS=$((PASS + 1))
    else
      echo "  FAIL  $name (expected pass, got errors)"
      echo "        $output"
      FAIL=$((FAIL + 1))
    fi
  else
    if echo "$output" | grep -q "type error"; then
      echo "  PASS  $name"
      PASS=$((PASS + 1))
    else
      echo "  FAIL  $name (expected error, got OK)"
      FAIL=$((FAIL + 1))
    fi
  fi
}

echo "Checker golden tests"
echo "===================="

run_case pass_let pass
run_case pass_infer pass
run_case pass_scope pass
run_case fail_mismatch fail

echo "===================="
echo "$PASS/$TOTAL passed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
