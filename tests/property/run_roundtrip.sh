#!/usr/bin/env bash
# Property: parse → print → re-print stability (decision 0012 phase 5).
#
# For each corpus file we run the selfhost front-end twice and require
# byte-identical output:
#   --ast    AST dump stability (parse + print AST)
#   (default) token dump stability (scan + print tokens)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET_BIN=$(resolve_kinglet "$ROOT") || exit 2
export KINGLET_BIN
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET_BIN") || exit 2

PER_CASE_TIMEOUT="${PER_CASE_TIMEOUT:-15}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CORPUS_FILE="$TMP/corpus.txt"
{
  find "$ROOT/tests/property/cases" -name '*.kl' -type f 2>/dev/null
  find "$ROOT/tests/parser/cases" -name '*.kl' -type f 2>/dev/null
} | awk -F/ '{print $NF "\t" $0}' | sort -u -t$'\t' -k1,1 | cut -f2- >"$CORPUS_FILE"

FAILURES=0
PASSED=0

run_twice() {
  local mode="$1"
  local src="$2"
  local name="$3"
  local label="$4"
  local out1="$TMP/${name}.${label}.1"
  local out2="$TMP/${name}.${label}.2"
  local err="$TMP/${name}.${label}.err"
  local ec1 ec2

  if [[ "$mode" == "--ast" ]]; then
    run_with_timeout "$PER_CASE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" --ast "$src" >"$out1" 2>"$err"
    ec1=$?
    run_with_timeout "$PER_CASE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" --ast "$src" >"$out2" 2>"$err"
    ec2=$?
  else
    run_with_timeout "$PER_CASE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" "$src" >"$out1" 2>"$err"
    ec1=$?
    run_with_timeout "$PER_CASE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" "$src" >"$out2" 2>"$err"
    ec2=$?
  fi
  strip_cr "$out1" "$out2"

  if [[ "$ec1" -eq 124 || "$ec2" -eq 124 ]]; then
    echo "FAIL  $name ($label): timed out after ${PER_CASE_TIMEOUT}s" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ "$ec1" -ne "$ec2" ]]; then
    echo "FAIL  $name ($label): exit $ec1 vs $ec2" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! diff -q "$out1" "$out2" >/dev/null 2>&1; then
    echo "FAIL  $name ($label): non-deterministic output" >&2
    diff -u "$out1" "$out2" | sed 's/^/      /' | head -15 >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS  $name ($label)"
  PASSED=$((PASSED + 1))
}

echo "=== Property round-trip (AST + token stability) ==="
while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  name=$(basename "$src" .kl)
  run_twice "--ast" "$src" "$name" "ast"
  run_twice "" "$src" "$name" "tokens"
done <"$CORPUS_FILE"

echo "===================="
echo "Passed: $PASSED  Failed: $FAILURES"
[[ "$FAILURES" -eq 0 ]]
