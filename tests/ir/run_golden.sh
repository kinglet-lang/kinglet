#!/usr/bin/env bash
# KIR golden tests — bootstrap `kinglet --ir` vs stored .kir files.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
BOOTSTRAP="${KINGLET_BOOTSTRAP:-}"

CASES_DIR="$ROOT/tests/ir/cases"
FAILURES=0

run_case() {
  local name="$1"
  local src="$CASES_DIR/$name.kl"
  local golden="$CASES_DIR/$name.kir"
  local out
  out="$(mktemp)"

  if ! "$BOOTSTRAP" --ir "$src" >"$out" 2>/dev/null; then
    echo "FAIL $name: bootstrap --ir exited non-zero" >&2
    rm -f "$out"
    FAILURES=$((FAILURES + 1))
    return
  fi

  strip_cr "$out" "$golden"

  if ! diff -u "$golden" "$out" >/dev/null; then
    echo "FAIL $name: KIR mismatch" >&2
    diff -u "$golden" "$out" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS $name"
  fi
  rm -f "$out"
}

for kl in "$CASES_DIR"/*.kl; do
  [[ -f "$kl" ]] || continue
  base="$(basename "$kl" .kl)"
  [[ -f "$CASES_DIR/$base.kir" ]] || continue
  run_case "$base"
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "KIR golden tests failed: $FAILURES" >&2
  exit 1
fi

echo "KIR golden tests passed."
