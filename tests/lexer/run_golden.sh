#!/usr/bin/env bash
# Lexer golden tests for the self-hosted Kinglet lexer.
# Runs native `.kinglet/out/compiler` on each case (default mode → token dump).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_COMPILER=$(ensure_native_compiler "$ROOT") || exit 2

CASES_DIR="$ROOT/tests/lexer/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

shopt -s nullglob
for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.tokens"
  if [[ ! -f "$golden" ]]; then
    echo "SKIP $name (no .tokens golden)" >&2
    continue
  fi
  out="$TMP_DIR/$name.out"
  err="$TMP_DIR/$name.err"

  "$CLI_COMPILER" "$src" >"$out" 2>"$err"
  actual_exit=$?
  strip_cr "$out" "$err"

  if [[ "$actual_exit" -ne 0 ]]; then
    echo "FAIL $name: exit $actual_exit" >&2
    cat "$err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! diff -u --strip-trailing-cr "$golden" "$out" >/dev/null; then
    echo "FAIL $name: tokens mismatch" >&2
    diff -u --strip-trailing-cr "$golden" "$out" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  echo "PASS $name"
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES lexer golden test(s) failed." >&2
  exit 1
fi
echo "Lexer golden tests passed."
