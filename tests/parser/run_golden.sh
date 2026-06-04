#!/usr/bin/env bash
# Parser golden tests for the self-hosted Kinglet parser.
# Runs `kinglet --run compiler.kbc --ast <case>.kl` and diffs stdout against
# `<case>.ast`. Uses the cached compiler.kbc artefact so each case takes ~70ms
# instead of recompiling cli/main.kl from source.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET") || exit 2

CASES_DIR="$ROOT/tests/parser/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0

# Cases the self-hosted parser hangs on. Each entry is a base name (no .kl).
# Documented bugs the suite skips with SKIP_KNOWN rather than blocking
# unrelated regressions. When the underlying issue is fixed, remove from
# this list and the case will start running again.
SKIP_KNOWN=()

# Per-case wall-clock cap. The default fast path is ~70-90ms per case,
# so 30s is a generous safety net that still catches regressions.
PER_CASE_TIMEOUT="${PER_CASE_TIMEOUT:-30}"

is_known_bad() {
  local name="$1"
  if ((${#SKIP_KNOWN[@]} == 0)); then return 1; fi
  for bad in "${SKIP_KNOWN[@]}"; do
    if [[ "$bad" == "$name" ]]; then return 0; fi
  done
  return 1
}

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

shopt -s nullglob
for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.ast"
  if [[ ! -f "$golden" ]]; then
    echo "SKIP $name (no .ast golden)" >&2
    continue
  fi
  if is_known_bad "$name"; then
    echo "SKIP_KNOWN $name (self-host parser hangs — see SKIP_KNOWN in run_golden.sh)"
    continue
  fi
  out="$TMP_DIR/$name.out"
  err="$TMP_DIR/$name.err"

  timeout "$PER_CASE_TIMEOUT" "$KINGLET" --run "$CLI_KBC" --ast "$src" >"$out" 2>"$err"
  actual_exit=$?
  strip_cr "$out" "$err"

  if [[ "$actual_exit" -eq 124 ]]; then
    echo "FAIL $name: timed out after ${PER_CASE_TIMEOUT}s" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if [[ "$actual_exit" -ne 0 ]]; then
    echo "FAIL $name: exit $actual_exit" >&2
    cat "$err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! diff -u --strip-trailing-cr "$golden" "$out" >/dev/null; then
    echo "FAIL $name: ast mismatch" >&2
    diff -u --strip-trailing-cr "$golden" "$out" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  echo "PASS $name"
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES parser golden test(s) failed." >&2
  exit 1
fi
echo "Parser golden tests passed."
