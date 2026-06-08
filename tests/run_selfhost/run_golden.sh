#!/usr/bin/env bash
# Behavioral tests executed through the self-hosted compiler.
#
# Pipeline per case:
#   1. kinglet --run compiler.kbc --save-bytecode <case>.kbc <case>.kl
#   2. kinglet --run <case>.kbc
# Compare stdout / exit code against <case>.expected and optional <case>.exit.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

CASES_DIR="$ROOT/tests/run_selfhost/cases"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

shopt -s nullglob
for src in "$CASES_DIR"/*.kl; do
  name=$(basename "$src" .kl)
  golden="$CASES_DIR/$name.expected"
  exit_file="$CASES_DIR/$name.exit"
  if [[ ! -f "$golden" ]]; then
    echo "SKIP $name (no .expected file)" >&2
    continue
  fi

  local_kbc="$TMP_DIR/$name.kbc"
  stdout="$TMP_DIR/$name.stdout"
  stderr="$TMP_DIR/$name.stderr"
  expected_exit=0
  if [[ -f "$exit_file" ]]; then
    expected_exit=$(cat "$exit_file")
  fi

  if ! compile_selfhost "$CLI_KBC" "$src" "$local_kbc" 2>"$stderr"; then
    echo "FAIL $name: self-host compile failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi

  actual_exit=0
  run_kbc "$local_kbc" >"$stdout" 2>>"$stderr" || actual_exit=$?
  strip_cr "$stdout" "$stderr"

  failed=0
  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL $name: exit want=$expected_exit got=$actual_exit" >&2
    failed=1
  fi
  if ! diff -u --strip-trailing-cr "$golden" "$stdout" >/dev/null 2>&1; then
    echo "FAIL $name: stdout mismatch" >&2
    diff -u --strip-trailing-cr "$golden" "$stdout" | sed 's/^/      /' | head -20 >&2
    failed=1
  fi
  if [[ -s "$stderr" ]]; then
    echo "FAIL $name: unexpected stderr" >&2
    cat "$stderr" | sed 's/^/      /' >&2
    failed=1
  fi

  if [[ "$failed" -eq 0 ]]; then
    echo "PASS $name"
  else
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES selfhost behavioral test(s) failed." >&2
  exit 1
fi
echo "Selfhost behavioral tests passed."
