#!/usr/bin/env bash
# Native smoke tests — bootstrap `kinglet --native` vs VM exit semantics.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
BOOTSTRAP="${KINGLET_BOOTSTRAP:-}"
CASES_DIR="$ROOT/tests/native/cases"
MANIFEST="$ROOT/tests/native/manifest.txt"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$MANIFEST" ]]; then
  echo "native manifest missing: $MANIFEST" >&2
  exit 1
fi

probe_native() {
  local err="$TMP_DIR/probe.err"
  local out="$TMP_DIR/probe.bin"
  local probe="$CASES_DIR/just42.kl"
  if "$BOOTSTRAP" --native "$out" "$probe" 2>"$err"; then
    return 0
  fi
  if grep -q 'native backend not built' "$err"; then
    echo "SKIP native smoke: bootstrap built without enable_llvm=true" >&2
    exit 0
  fi
  echo "native probe failed:" >&2
  cat "$err" >&2
  exit 1
}

probe_native

run_case() {
  local name="$1"
  local src="$CASES_DIR/$name.kl"
  local bin="$TMP_DIR/$name"
  local stderr="$TMP_DIR/$name.err"
  local want_exit=0
  local ec=0

  if [[ ! -f "$src" ]]; then
    echo "FAIL $name: missing $src" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -f "$CASES_DIR/$name.exit" ]]; then
    want_exit=$(cat "$CASES_DIR/$name.exit")
  fi

  if ! "$BOOTSTRAP" --native "$bin" "$src" 2>"$stderr"; then
    echo "FAIL $name: --native compile failed" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  "$bin" 2>>"$stderr" || ec=$?
  strip_cr "$stderr"

  if [[ "$ec" -ne "$want_exit" ]]; then
    echo "FAIL $name: exit want=$want_exit got=$ec" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [[ -s "$stderr" ]]; then
    echo "FAIL $name: stderr not empty" >&2
    cat "$stderr" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS $name"
}

while IFS= read -r name || [[ -n "$name" ]]; do
  [[ -z "$name" ]] && continue
  [[ "$name" =~ ^# ]] && continue
  run_case "$name"
done <"$MANIFEST"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Native smoke tests failed: $FAILURES" >&2
  exit 1
fi
echo "Native smoke tests passed."
