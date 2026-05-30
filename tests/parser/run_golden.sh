#!/usr/bin/env bash
# Parser golden tests for the self-hosted Kinglet parser.
# Runs `kinglet cli/main.kl --ast <case>.kl` and diffs stdout against `<case>.ast`.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Default location of the bootstrap kinglet binary (built from the C++
# implementation living at <repo>/../../kinglet). Override via KINGLET=...
KINGLET="${KINGLET:-$ROOT/../../kinglet/out/Debug/kinglet}"
ENTRY="$ROOT/cli/main.kl"
CASES_DIR="$ROOT/tests/parser/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -x "$KINGLET" && ! -x "$KINGLET.exe" && ! -f "$KINGLET" && ! -f "$KINGLET.exe" ]]; then
  echo "kinglet binary not found at $KINGLET" >&2
  echo "Set KINGLET=/path/to/kinglet to override." >&2
  exit 2
fi

shopt -s nullglob
for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.ast"
  if [[ ! -f "$golden" ]]; then
    echo "SKIP $name (no .ast golden)" >&2
    continue
  fi
  out="$TMP_DIR/$name.out"
  err="$TMP_DIR/$name.err"

  "$KINGLET" "$ENTRY" --ast "$src" >"$out" 2>"$err"
  actual_exit=$?
  sed -i 's/\r$//' "$out" "$err" 2>/dev/null

  if [[ "$actual_exit" -ne 0 ]]; then
    echo "FAIL $name: exit $actual_exit" >&2
    cat "$err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! diff -u "$golden" "$out" >/dev/null; then
    echo "FAIL $name: ast mismatch" >&2
    diff -u "$golden" "$out" >&2
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
