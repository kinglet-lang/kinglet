#!/usr/bin/env bash
# Codegen golden tests for the self-hosted Kinglet bytecode compiler.
#
# For each case <name>.kl we run:
#   kinglet --run compiler.kbc --bytecode <name>.kl
# and compare against the stored <name>.bytecode golden file.
#
# A subset of cases also get a compile+run smoke step (runtime backstop).
# Cases with <name>.expected assert stdout after a successful run.
#
# Regenerate goldens: bash tests/codegen/refresh_goldens.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

CASES_DIR="$ROOT/tests/codegen/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0
GOLDEN_PASSES=0
SMOKE_PASSES=0

# Representative cases: bytecode golden + selfhost compile + VM run (no crash).
SMOKE_CASES=(
  addmain array_basic array_methods cast_basic compound_assign
  for_basic if_basic if_else just42 match_enum_payload
  match_enum_simple native_io struct_basic unary
)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

is_smoke_case() {
  local name="$1"
  local c
  for c in "${SMOKE_CASES[@]}"; do
    [[ "$c" == "$name" ]] && return 0
  done
  return 1
}

run_smoke() {
  local name="$1"
  local src="$CASES_DIR/$name.kl"
  local kbc="$TMP_DIR/$name.kbc"
  local stdout="$TMP_DIR/$name.stdout"
  local stderr="$TMP_DIR/$name.stderr"
  local expected="$CASES_DIR/$name.expected"
  local exit_file="$CASES_DIR/$name.exit"
  local want_exit=0
  if [[ -f "$exit_file" ]]; then
    want_exit=$(cat "$exit_file")
  fi

  compile_selfhost "$CLI_KBC" "$src" "$kbc" 2>"$stderr" || {
    echo "FAIL $name: smoke compile failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  }

  local ec=0
  run_kbc "$kbc" >"$stdout" 2>>"$stderr" || ec=$?
  strip_cr "$stdout" "$stderr"

  if [[ "$ec" -ne "$want_exit" ]]; then
    echo "FAIL $name: smoke run exit want=$want_exit got=$ec" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -s "$stderr" ]]; then
    echo "FAIL $name: smoke run produced stderr" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -f "$expected" ]]; then
    if ! diff -u "$expected" "$stdout" >/dev/null 2>&1; then
      echo "FAIL $name: smoke stdout mismatch" >&2
      diff -u "$expected" "$stdout" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
  fi
  echo "SMOKE $name"
  SMOKE_PASSES=$((SMOKE_PASSES + 1))
}

shopt -s nullglob
for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.bytecode"
  if [[ ! -f "$golden" ]]; then
    echo "SKIP $name (no .bytecode golden)"
    continue
  fi
  self_out="$TMP_DIR/$name.out"
  self_err="$TMP_DIR/$name.err"

  run_kbc "$CLI_KBC" --bytecode "$src" >"$self_out" 2>"$self_err"
  self_exit=$?
  strip_cr "$self_out"

  if [[ "$self_exit" -ne 0 ]]; then
    echo "FAIL $name: self-host --bytecode exited $self_exit" >&2
    cat "$self_err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! diff -u --strip-trailing-cr "$golden" "$self_out" >/dev/null; then
    echo "FAIL $name: bytecode mismatch" >&2
    diff -u --strip-trailing-cr "$golden" "$self_out" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  echo "PASS $name"
  GOLDEN_PASSES=$((GOLDEN_PASSES + 1))

  if is_smoke_case "$name"; then
    run_smoke "$name"
  fi
done

echo "Golden: $GOLDEN_PASSES  Smoke: $SMOKE_PASSES  Failed: $FAILURES"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES codegen test(s) failed." >&2
  exit 1
fi
echo "Codegen golden tests passed."
