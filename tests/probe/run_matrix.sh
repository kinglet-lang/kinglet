#!/usr/bin/env bash
# Capability matrix probe runner for selfhost compiler.
#
# For each probe in cases/*.kl, runs the compiler through four stages:
# parse → check → codegen → run, recording the FURTHEST stage reached.
#
# The run-stage oracle is the probe's line-1 `// EXPECT_OUT: <text>` comment.
#
# This is a capability SNAPSHOT, not a pass/fail gate: it always exits 0 and
# prints how far each probe gets, documenting known gaps as well as supported
# features.
#
# Ported from kinglet-bootstrap/tests/probe/run_matrix.sh.
# Implements Phase 2a from handoff/02-test-suite-plan.md.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2

CASES="$ROOT/tests/probe/cases"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Classify probe by furthest stage reached.
# parse / check / codegen expect clean exit; run compares stdout to EXPECT_OUT.
classify() {
  local f="$1" expect="$2"

  # Stage 1: Parse (--ast)
  "$KINGLET" --ast "$f" >/dev/null 2>"$TMP/e" || {
    echo "parse✗|$(head -1 "$TMP/e")"
    return
  }

  # Stage 2: Check (--check)
  "$KINGLET" --check "$f" >/dev/null 2>"$TMP/e" || {
    echo "chk✗|$(head -1 "$TMP/e")"
    return
  }

  # Stage 3: Codegen (--bytecode)
  "$KINGLET" --bytecode "$f" >/dev/null 2>"$TMP/e" || {
    echo "cg✗|$(head -1 "$TMP/e")"
    return
  }

  # Stage 4: Run (execute and compare output)
  local out
  out=$("$KINGLET" "$f" 2>"$TMP/e"); local ec=$?

  if [[ $ec -ne 0 ]]; then
    echo "run✗(rt)|$(head -1 "$TMP/e")"
    return
  fi

  if [[ "$out" == "$expect" ]]; then
    echo "run✓|"
  else
    echo "run≠out|got:'$out'"
  fi
}

echo "# Kinglet capability matrix (selfhost)"
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo
printf '| %-30s | %-12s | %-12s | %s |\n' "probe" "expect" "stage" "note"
printf '|%s|%s|%s|%s|\n' "--------------------------------" "--------------" "--------------" "----------------"

reached_run=0
total=0

shopt -s nullglob
for f in "$CASES"/*.kl; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .kl)

  # Extract oracle from line 1: // EXPECT_OUT: <text>
  expect=$(head -1 "$f" | sed -n 's/.*EXPECT_OUT:[[:space:]]*\(.*\)/\1/p')
  [[ -z "$expect" ]] && expect="<no oracle>"

  total=$((total + 1))

  res=$(classify "$f" "$expect")
  cell=${res%%|*}
  note=${res#*|}

  [[ "$cell" == "run✓" ]] && reached_run=$((reached_run + 1))

  printf '| %-30s | %-12s | %-12s | %s |\n' "$name" "$expect" "$cell" "$note"
done

echo
echo "Total: $total probes, run✓: $reached_run"
echo
echo "Legend:"
echo "  parse✗ = parse failed"
echo "  chk✗   = type check failed"
echo "  cg✗    = codegen failed"
echo "  run✗   = runtime error"
echo "  run≠out = output mismatch"
echo "  run✓   = passed all stages"
