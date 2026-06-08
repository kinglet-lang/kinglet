#!/usr/bin/env bash
# Compare bootstrap compiler.kbc vs selfhost fixed-point S3 for core/main.kl.
#
# Informational: bootstrap byte-identical parity is not required for round-trip
# fixed-point (S3 == S4). This script quantifies remaining delta.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/tests/common.sh"

export_kinglet_bins "$ROOT" || exit 2
CLI_KBC=$(ensure_cli_kbc "$ROOT") || exit 2

ENTRY="$ROOT/core/main.kl"
COMPILE_TIMEOUT="${KINGLET_COMPILE_TIMEOUT:-600}"
TMP_DIR="$(mktemp -d)"
S2_KBC="$TMP_DIR/S2.kbc"
S3_KBC="$TMP_DIR/S3.kbc"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "=== Bootstrap vs selfhost bytecode diff ==="
echo

echo "Bootstrap: $CLI_KBC ($(stat -c%s "$CLI_KBC" 2>/dev/null || stat -f%z "$CLI_KBC") bytes)"
echo

echo "Step 1: S2 = compiler.kbc compiles core/main.kl"
if ! run_with_timeout "$COMPILE_TIMEOUT" "$KINGLET_BIN" --run "$CLI_KBC" --save-bytecode \
    "$S2_KBC" "$ENTRY" 2>"$TMP_DIR/s2.err"; then
  echo "FAIL: S2 compile failed" >&2
  cat "$TMP_DIR/s2.err" >&2
  exit 1
fi
echo "  S2: $(stat -c%s "$S2_KBC" 2>/dev/null || stat -f%z "$S2_KBC") bytes"
echo

echo "Step 2: S3 = S2 compiles core/main.kl (fixed-point artefact)"
if ! run_with_timeout "$COMPILE_TIMEOUT" "$KINGLET_BIN" --run "$S2_KBC" --save-bytecode \
    "$S3_KBC" "$ENTRY" 2>"$TMP_DIR/s3.err"; then
  echo "FAIL: S3 compile failed" >&2
  cat "$TMP_DIR/s3.err" >&2
  exit 1
fi
echo "  S3: $(stat -c%s "$S3_KBC" 2>/dev/null || stat -f%z "$S3_KBC") bytes"
echo

if cmp -s "$S2_KBC" "$S3_KBC"; then
  echo "S2 == S3 (selfhost stable)"
else
  echo "WARN: S2 != S3 (unexpected before bootstrap diff)" >&2
fi
echo

if cmp -s "$CLI_KBC" "$S3_KBC"; then
  echo "PASS: bootstrap compiler.kbc is byte-identical to S3"
  exit 0
fi

echo "Bootstrap parity: NOT byte-identical (structured diff below)"
echo
python3 "$ROOT/tests/tools/kbc_diff.py" "$CLI_KBC" "$S3_KBC"
exit 0
