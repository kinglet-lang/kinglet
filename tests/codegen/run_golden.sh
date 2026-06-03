#!/usr/bin/env bash
# Codegen golden tests for the self-hosted Kinglet bytecode compiler.
#
# For each case <name>.kl we compare:
#   self-host:  kinglet --run cli.kbc --bytecode <name>.kl
#   C++ truth:  kinglet --bytecode <name>.kl
#
# These must be byte-equal. C++ output is treated as ground truth — drift
# in either implementation surfaces here.
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
  cpp_out="$TMP_DIR/$name.cpp"
  self_out="$TMP_DIR/$name.self"

  "$KINGLET" --bytecode "$src" >"$cpp_out" 2>"$TMP_DIR/$name.cpp.err"
  cpp_exit=$?
  "$KINGLET" --run "$CLI_KBC" --bytecode "$src" >"$self_out" 2>"$TMP_DIR/$name.self.err"
  self_exit=$?
  perl -i -pe 's/\r$//' "$cpp_out" "$self_out"

  if [[ "$cpp_exit" -ne 0 ]]; then
    echo "FAIL $name: C++ --bytecode exited $cpp_exit" >&2
    cat "$TMP_DIR/$name.cpp.err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if [[ "$self_exit" -ne 0 ]]; then
    echo "FAIL $name: self-host --bytecode exited $self_exit" >&2
    cat "$TMP_DIR/$name.self.err" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! diff -u --strip-trailing-cr "$cpp_out" "$self_out" >/dev/null; then
    echo "FAIL $name: bytecode mismatch (left=cpp, right=self)" >&2
    diff -u --strip-trailing-cr "$cpp_out" "$self_out" >&2
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
