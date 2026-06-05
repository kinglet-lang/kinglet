#!/usr/bin/env bash
# Codegen golden tests for the self-hosted Kinglet bytecode compiler.
#
# For each case <name>.kl we run:
#   self-host:  kinglet --run compiler.kbc --bytecode <name>.kl
# and compare against the stored <name>.bytecode golden file.
#
# Golden files were regenerated from self-host output when the test suite
# migrated from C++-bootstrap-focused to self-host-focused testing.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

KINGLET=$(resolve_kinglet "$ROOT") || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT" "$KINGLET") || exit 2

CASES_DIR="$ROOT/tests/codegen/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

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
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES codegen golden test(s) failed." >&2
  exit 1
fi
echo "Codegen golden tests passed."
